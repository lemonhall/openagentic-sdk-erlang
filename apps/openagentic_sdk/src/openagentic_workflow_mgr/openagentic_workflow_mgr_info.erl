-module(openagentic_workflow_mgr_info).
-export([handle_cast/2, handle_info/2, init/1]).

-define(TICK_MS, 5000).

init(State0) ->
  _ = erlang:send_after(?TICK_MS, self(), tick),
  {ok, openagentic_workflow_mgr_utils:ensure_map(State0)}.

handle_cast({note_progress, WfSid, Ev0}, State0) ->
  Ev = openagentic_workflow_mgr_utils:ensure_map(Ev0),
  Now = openagentic_workflow_mgr_utils:now_ms(),
  EvType = openagentic_workflow_mgr_status:event_progress_type(Ev),
  case maps:find(WfSid, State0) of
    {ok, Item0} -> {noreply, State0#{WfSid => Item0#{last_progress_ms => Now, last_event_type => EvType}}};
    error -> {noreply, State0}
  end;
handle_cast(_Msg, State0) ->
  {noreply, State0}.

handle_info({'DOWN', MRef, process, Pid, _Reason}, State0) ->
  case openagentic_workflow_mgr_tracking:find_by_monitor(MRef, Pid, State0) of
    {ok, WfSid, Item0} ->
      Q0 = openagentic_workflow_mgr_utils:ensure_list_value(maps:get(queue, Item0, [])),
      SessionRoot = openagentic_workflow_mgr_utils:ensure_list(maps:get(session_root, Item0, "")),
      EngineOpts = openagentic_workflow_mgr_utils:ensure_map(maps:get(engine_opts, Item0, #{})),
      State1 = maps:remove(WfSid, State0),
      case Q0 of
        [] -> {noreply, State1};
        [NextMsg | Rest] ->
          case openagentic_workflow_engine:continue_start(SessionRoot, openagentic_workflow_mgr_utils:ensure_list(WfSid), NextMsg, EngineOpts) of
            {ok, Info} ->
              NextPid = maps:get(pid, Info, undefined),
              Item1 = (maps:remove(pid, Item0))#{queue := Rest},
              State2 = openagentic_workflow_mgr_tracking:maybe_track_runner(WfSid, NextPid, SessionRoot, EngineOpts, State1#{WfSid => Item1}),
              {noreply, State2};
            _ -> {noreply, State1}
          end
      end;
    error -> {noreply, State0}
  end;
handle_info(tick, State0) ->
  State1 = openagentic_workflow_mgr_stalls:check_stalls(openagentic_workflow_mgr_utils:now_ms(), State0),
  _ = erlang:send_after(?TICK_MS, self(), tick),
  {noreply, State1};
handle_info(_Other, State0) ->
  {noreply, State0}.
