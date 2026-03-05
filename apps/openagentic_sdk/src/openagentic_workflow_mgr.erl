-module(openagentic_workflow_mgr).

-behaviour(gen_server).

-export([start_link/0, ensure_started/0]).
-export([start_workflow/4, continue_workflow/4, cancel_workflow/2, status/1]).
-export([note_progress/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% A minimal workflow run manager (web-friendly).
%%
%% Goals:
%% - Ensure at most one runner per workflow_session_id.
%% - Allow "continue" messages while a workflow is running by queueing them.
%% - Provide cancellation to recover from stuck runs.
%%
%% Notes:
%% - State is in-memory only (v1).
%% - Runner processes are owned by openagentic_workflow_engine (start/continue_start).

-define(SERVER, ?MODULE).
-define(TICK_MS, 5000).
-define(DEFAULT_IDLE_TIMEOUT_MS, 120 * 1000).
-define(DEFAULT_QUESTION_TIMEOUT_MS, 10 * 60 * 1000).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, #{}, []).

ensure_started() ->
  case whereis(?SERVER) of
    undefined ->
      case start_link() of
        {ok, _Pid} -> ok;
        {error, {already_started, _}} -> ok;
        Other -> erlang:error({workflow_mgr_start_failed, Other})
      end;
    _ ->
      ok
  end.

%% Start a new workflow run (new workflow session).
start_workflow(ProjectDir, WorkflowRelPath, Prompt, EngineOpts) ->
  ensure_started(),
  gen_server:call(?SERVER, {start_workflow, ProjectDir, WorkflowRelPath, Prompt, EngineOpts}, 60000).

%% Continue an existing workflow session.
%% If it is currently running, the message is queued and will be processed after current runner exits.
continue_workflow(SessionRoot, WorkflowSessionId, Message, EngineOpts) ->
  ensure_started(),
  gen_server:call(?SERVER, {continue_workflow, SessionRoot, WorkflowSessionId, Message, EngineOpts}, 60000).

cancel_workflow(SessionRoot, WorkflowSessionId) ->
  ensure_started(),
  gen_server:call(?SERVER, {cancel_workflow, SessionRoot, WorkflowSessionId}, 60000).

status(WorkflowSessionId) ->
  ensure_started(),
  gen_server:call(?SERVER, {status, WorkflowSessionId}, 60000).

note_progress(WorkflowSessionId0, Event0) ->
  ensure_started(),
  gen_server:cast(?SERVER, {note_progress, to_bin(WorkflowSessionId0), ensure_map(Event0)}).

init(State0) ->
  _ = erlang:send_after(?TICK_MS, self(), tick),
  {ok, ensure_map(State0)}.

handle_call({start_workflow, ProjectDir, WorkflowRelPath, Prompt, EngineOpts0}, _From, State0) ->
  EngineOpts = ensure_map(EngineOpts0),
  Res = openagentic_workflow_engine:start(ProjectDir, WorkflowRelPath, Prompt, EngineOpts),
  case Res of
    {ok, Info} ->
      WfSid = to_bin(maps:get(workflow_session_id, Info, <<>>)),
      Pid = maps:get(pid, Info, undefined),
      State1 = maybe_track_runner(WfSid, Pid, ensure_list(session_root_from_opts(EngineOpts)), EngineOpts, State0),
      {reply, {ok, Info#{queued => false, queue_length => 0}}, State1};
    Err ->
      {reply, Err, State0}
  end;
handle_call({continue_workflow, SessionRoot0, WorkflowSessionId0, Message0, EngineOpts0}, _From, State0) ->
  SessionRoot = ensure_list(SessionRoot0),
  WorkflowSessionId = to_bin(WorkflowSessionId0),
  Message = to_bin(Message0),
  EngineOpts = ensure_map(EngineOpts0),
  case is_running(WorkflowSessionId, State0) of
    {true, Item0} ->
      Q0 = ensure_list_value(maps:get(queue, Item0, [])),
      Q = Q0 ++ [Message],
      Item = Item0#{queue := Q, session_root := SessionRoot, engine_opts := EngineOpts},
      State1 = State0#{WorkflowSessionId => Item},
      Reply = #{queued => true, queue_length => length(Q)},
      {reply, {ok, Reply}, State1};
    false ->
      Res = openagentic_workflow_engine:continue_start(SessionRoot, ensure_list(WorkflowSessionId), Message, EngineOpts),
      case Res of
        {ok, Info} ->
          Pid = maps:get(pid, Info, undefined),
          State1 = maybe_track_runner(WorkflowSessionId, Pid, SessionRoot, EngineOpts, State0),
          Reply = Info#{queued => false, queue_length => 0},
          {reply, {ok, Reply}, State1};
        Err ->
          {reply, Err, State0}
      end
  end;
handle_call({cancel_workflow, SessionRoot0, WorkflowSessionId0}, _From, State0) ->
  _SessionRoot = ensure_list(SessionRoot0),
  WorkflowSessionId = to_bin(WorkflowSessionId0),
  case maps:find(WorkflowSessionId, State0) of
    {ok, Item0} ->
      _ = maybe_kill_pid(maps:get(pid, Item0, undefined)),
      State1 = maps:remove(WorkflowSessionId, State0),
      {reply, {ok, #{ok => true, canceled => true}}, State1};
    error ->
      %% Nothing to cancel; treat as ok.
      {reply, {ok, #{ok => true, canceled => false}}, State0}
  end;
handle_call({status, WorkflowSessionId0}, _From, State0) ->
  WorkflowSessionId = to_bin(WorkflowSessionId0),
  case is_running(WorkflowSessionId, State0) of
    {true, Item} ->
      Reply = #{running => true, queue_length => length(ensure_list_value(maps:get(queue, Item, [])))},
      {reply, {ok, Reply}, State0};
    false ->
      {reply, {ok, #{running => false, queue_length => 0}}, State0}
  end;
handle_call(_Other, _From, State0) ->
  {reply, {error, bad_request}, State0}.

handle_cast({note_progress, WfSid, Ev0}, State0) ->
  Ev = ensure_map(Ev0),
  Now = now_ms(),
  EvType = to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))),
  case maps:find(WfSid, State0) of
    {ok, Item0} ->
      Item = Item0#{last_progress_ms => Now, last_event_type => EvType},
      {noreply, State0#{WfSid => Item}};
    error ->
      {noreply, State0}
  end;
handle_cast(_Msg, State0) ->
  {noreply, State0}.

handle_info({'DOWN', MRef, process, Pid, _Reason}, State0) ->
  case find_by_monitor(MRef, Pid, State0) of
    {ok, WfSid, Item0} ->
      Q0 = ensure_list_value(maps:get(queue, Item0, [])),
      SessionRoot = ensure_list(maps:get(session_root, Item0, "")),
      EngineOpts = ensure_map(maps:get(engine_opts, Item0, #{})),
      State1 = maps:remove(WfSid, State0),
      case Q0 of
        [] ->
          {noreply, State1};
        [NextMsg | Rest] ->
          %% Start next queued continue run.
          Res = openagentic_workflow_engine:continue_start(SessionRoot, ensure_list(WfSid), NextMsg, EngineOpts),
          case Res of
            {ok, Info} ->
              NextPid = maps:get(pid, Info, undefined),
              Item1 = (maps:remove(pid, Item0))#{queue := Rest},
              State2 = maybe_track_runner(WfSid, NextPid, SessionRoot, EngineOpts, State1#{WfSid => Item1}),
              {noreply, State2};
            _ ->
              %% Drop queue on repeated failure; allow user to re-try manually.
              {noreply, State1}
          end
      end;
    error ->
      {noreply, State0}
  end;
handle_info(tick, State0) ->
  Now = now_ms(),
  State1 = check_stalls(Now, State0),
  _ = erlang:send_after(?TICK_MS, self(), tick),
  {noreply, State1};
handle_info(_Other, State0) ->
  {noreply, State0}.

%% ---- internal ----

maybe_track_runner(WfSid0, Pid0, SessionRoot0, EngineOpts0, State0) ->
  WfSid = to_bin(WfSid0),
  SessionRoot = ensure_list(SessionRoot0),
  EngineOpts = ensure_map(EngineOpts0),
  case is_pid(Pid0) andalso is_process_alive(Pid0) of
    true ->
      MRef = erlang:monitor(process, Pid0),
      Item0 = ensure_map(maps:get(WfSid, State0, #{})),
      Now = now_ms(),
      Item =
        Item0#{
          pid => Pid0,
          mon_ref => MRef,
          queue => ensure_list_value(maps:get(queue, Item0, [])),
          session_root => SessionRoot,
          engine_opts => EngineOpts,
          last_progress_ms => maps:get(last_progress_ms, Item0, Now),
          last_event_type => maps:get(last_event_type, Item0, <<>>)
        },
      State0#{WfSid => Item};
    false ->
      State0
  end.

is_running(WfSid0, State0) ->
  WfSid = to_bin(WfSid0),
  case maps:find(WfSid, State0) of
    {ok, Item} ->
      Pid = maps:get(pid, Item, undefined),
      case is_pid(Pid) andalso is_process_alive(Pid) of
        true -> {true, Item};
        false -> false
      end;
    error ->
      false
  end.

find_by_monitor(MRef0, Pid0, State0) ->
  MRef = MRef0,
  Pid = Pid0,
  Keys = maps:keys(State0),
  find_by_monitor_keys(Keys, MRef, Pid, State0).

find_by_monitor_keys([], _MRef, _Pid, _State0) ->
  error;
find_by_monitor_keys([K | Rest], MRef, Pid, State0) ->
  Item = ensure_map(maps:get(K, State0, #{})),
  case {maps:get(mon_ref, Item, undefined), maps:get(pid, Item, undefined)} of
    {MRef, Pid} ->
      {ok, K, Item};
    _ ->
      find_by_monitor_keys(Rest, MRef, Pid, State0)
  end.

maybe_kill_pid(Pid) when is_pid(Pid) ->
  catch exit(Pid, kill),
  ok;
maybe_kill_pid(_Other) ->
  ok.

check_stalls(Now, State0) ->
  Keys = maps:keys(State0),
  check_stalls_keys(Keys, Now, State0).

check_stalls_keys([], _Now, State0) ->
  State0;
check_stalls_keys([WfSid | Rest], Now, State0) ->
  Item0 = ensure_map(maps:get(WfSid, State0, #{})),
  Pid = maps:get(pid, Item0, undefined),
  case is_pid(Pid) andalso is_process_alive(Pid) of
    false ->
      check_stalls_keys(Rest, Now, maps:remove(WfSid, State0));
    true ->
      Last = maps:get(last_progress_ms, Item0, Now),
      EvType = to_bin(maps:get(last_event_type, Item0, <<>>)),
      EngineOpts = ensure_map(maps:get(engine_opts, Item0, #{})),
      IdleMs = idle_timeout_ms(EngineOpts),
      QuestionMs = question_timeout_ms(EngineOpts),
      TimeoutMs =
        case EvType of
          <<"user.question">> -> QuestionMs;
          _ -> IdleMs
        end,
      case (Now - Last) > TimeoutMs of
        true ->
          SessionRoot = ensure_list(maps:get(session_root, Item0, "")),
          _ = maybe_kill_pid(Pid),
          _ = append_stalled_done(SessionRoot, WfSid, EvType, TimeoutMs),
          %% Drop runner + allow queued continues to restart a new run.
          State1 = maps:remove(WfSid, State0),
          check_stalls_keys(Rest, Now, State1);
        false ->
          check_stalls_keys(Rest, Now, State0)
      end
  end.

idle_timeout_ms(EngineOpts0) ->
  EngineOpts = ensure_map(EngineOpts0),
  Sec0 = maps:get(idle_timeout_seconds, EngineOpts, maps:get(<<"idle_timeout_seconds">>, EngineOpts, undefined)),
  Sec = int_or_default(Sec0, ?DEFAULT_IDLE_TIMEOUT_MS div 1000),
  clamp_int(Sec, 5, 3600) * 1000.

question_timeout_ms(EngineOpts0) ->
  EngineOpts = ensure_map(EngineOpts0),
  Sec0 =
    maps:get(
      question_timeout_seconds,
      EngineOpts,
      maps:get(<<"question_timeout_seconds">>, EngineOpts, ?DEFAULT_QUESTION_TIMEOUT_MS div 1000)
    ),
  Sec = int_or_default(Sec0, ?DEFAULT_QUESTION_TIMEOUT_MS div 1000),
  clamp_int(Sec, 30, 3600) * 1000.

append_stalled_done(SessionRoot0, WorkflowSessionId0, LastEventType0, TimeoutMs0) ->
  SessionRoot = ensure_list(SessionRoot0),
  WfSid = ensure_list(WorkflowSessionId0),
  Dir = openagentic_session_store:session_dir(SessionRoot, WfSid),
  MetaPath = filename:join([Dir, "meta.json"]),
  {WfId, WfName} =
    case file:read_file(MetaPath) of
      {ok, Bin} ->
        case (catch openagentic_json:decode(Bin)) of
          M when is_map(M) ->
            Md = ensure_map(maps:get(<<"metadata">>, M, maps:get(metadata, M, #{}))),
            {
              to_bin(maps:get(<<"workflow_id">>, Md, maps:get(workflow_id, Md, <<>>))),
              to_bin(maps:get(<<"workflow_name">>, Md, maps:get(workflow_name, Md, <<>>)))
            };
          _ ->
            {<<>>, <<>>}
        end;
      _ ->
        {<<>>, <<>>}
    end,
  LastEventType = to_bin(LastEventType0),
  TimeoutMs = int_or_default(TimeoutMs0, ?DEFAULT_IDLE_TIMEOUT_MS),
  Msg =
    iolist_to_binary([
      <<"Watchdog: no new events for ">>,
      integer_to_binary(TimeoutMs),
      <<"ms (last_event_type=">>,
      LastEventType,
      <<"). Runner was cancelled; you can continue in-place or start a new run.">>
    ]),
  Ev = openagentic_events:workflow_done(WfId, WfName, <<"stalled">>, Msg, #{by => <<"watchdog">>}),
  _ = openagentic_session_store:append_event(SessionRoot, WfSid, Ev),
  ok.

session_root_from_opts(Opts0) ->
  Opts = ensure_map(Opts0),
  case maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined)) of
    undefined -> openagentic_paths:default_session_root();
    V -> V
  end.

now_ms() ->
  erlang:monotonic_time(millisecond).

clamp_int(I, Min, Max) when is_integer(I) ->
  erlang:min(Max, erlang:max(Min, I));
clamp_int(_Other, Min, _Max) ->
  Min.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(_) -> [].

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
