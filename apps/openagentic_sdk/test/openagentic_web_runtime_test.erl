-module(openagentic_web_runtime_test).

-include_lib("eunit/include/eunit.hrl").

web_runtime_supervisor_isolates_caller_from_internal_service_crash_test_() ->
  {timeout, 30, fun web_runtime_supervisor_isolates_caller_from_internal_service_crash_body/0}.

workflow_watchdog_visibility_and_continue_status_test_() ->
  {timeout, 45, fun workflow_watchdog_visibility_and_continue_status_body/0}.

web_question_broker_ignores_duplicate_answer_test_() ->
  {timeout, 10, fun web_question_broker_ignores_duplicate_answer_body/0}.

web_runtime_supervisor_isolates_caller_from_internal_service_crash_body() ->
  reset_web_runtime(),
  Root = tmp_root(),
  Port = pick_port(),
  Parent = self(),
  {Worker, MRef} =
    spawn_monitor(
      fun () ->
        {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
        Parent ! {worker_started, self()},
        receive
          stop -> ok
        end
      end
    ),
  receive
    {worker_started, Worker} -> ok
  after 5000 ->
    ?assert(false)
  end,
  ServicePid = wait_until(fun () -> whereis(openagentic_web_q) end, 5000),
  ?assert(is_pid(ServicePid)),
  exit(ServicePid, kill),
  RestartedServicePid =
    wait_until(
      fun () ->
        case whereis(openagentic_web_q) of
          Pid when is_pid(Pid), Pid =/= ServicePid -> Pid;
          _ -> false
        end
      end,
      5000
    ),
  ?assert(is_pid(RestartedServicePid)),
  timer:sleep(200),
  ?assert(is_process_alive(Worker)),
  Worker ! stop,
  receive
    {'DOWN', MRef, process, Worker, normal} -> ok;
    {'DOWN', MRef, process, Worker, Reason} -> ?assertEqual(normal, Reason)
  after 5000 ->
    ?assert(false)
  end,
  openagentic_web:stop(),
  reset_web_runtime(),
  ok.

workflow_watchdog_visibility_and_continue_status_body() ->
  reset_web_runtime(),
  ok = ensure_httpc_started(),
  Root = tmp_root(),
  ok = write_web_workflow(Root),
  Port = pick_port(),
  Tab = ets:new(web_runtime_watchdog_tab, [public]),
  Exec =
    fun (_Ctx) ->
      Call = ets:update_counter(Tab, exec_calls, 1, {exec_calls, 0}),
      case Call of
        1 ->
          ets:insert(Tab, {phase, stalled_once}),
          timer:sleep(15000),
          {ok, <<"# Summary\n\nlate\n">>};
        _ ->
          {ok, <<"# Summary\n\nok\n">>}
      end
    end,
  Opts = #{step_executor => Exec, strict_unknown_fields => true, idle_timeout_seconds => 1},
  {ok, #{url := Url0}} = openagentic_web:start(Opts#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
  Url = ensure_list(Url0),
  try
    {201, StartResp} = http_post_json(Url ++ "api/workflows/start", #{prompt => <<"hello">>, dsl => <<"workflows/w_web.json">>}),
    WfSid = maps:get(<<"workflow_session_id">>, StartResp),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, StartResp, <<>>)),

    {202, QueuedResp} = http_post_json(Url ++ "api/workflows/continue", #{workflow_session_id => WfSid, message => <<"follow up">>}),
    ?assertEqual(<<"queued">>, maps:get(<<"status">>, QueuedResp, <<>>)),
    ?assertEqual(true, maps:get(<<"queued">>, QueuedResp, false)),

    StalledDone =
      wait_until(
        fun () ->
          Events = openagentic_session_store:read_events(Root, ensure_list(WfSid)),
          find_last_workflow_done(Events, <<"stalled">>)
        end,
        12000
      ),
    ?assertEqual(<<"watchdog">>, maps:get(<<"by">>, StalledDone, <<>>)),

    {ok, StatusResp} = openagentic_workflow_mgr:status(Root, WfSid),
    ?assertEqual(<<"stalled">>, maps:get(status, StatusResp, <<>>)),

    {202, ResumeResp} = http_post_json(Url ++ "api/workflows/continue", #{workflow_session_id => WfSid, message => <<"resume">>}),
    ?assertEqual(<<"resumed_from_stalled">>, maps:get(<<"status">>, ResumeResp, <<>>)),
    ?assertEqual(true, maps:get(<<"resumed_from_stalled">>, ResumeResp, false)),
    ?assertEqual(<<"stalled">>, maps:get(<<"previous_status">>, ResumeResp, <<>>)),

    CompletedDone =
      wait_until(
        fun () ->
          Events = openagentic_session_store:read_events(Root, ensure_list(WfSid)),
          find_last_workflow_done(Events, <<"completed">>)
        end,
        8000
      ),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, CompletedDone, <<>>))
  after
    openagentic_web:stop(),
    ets:delete(Tab),
    reset_web_runtime()
  end,
  ok.

web_question_broker_ignores_duplicate_answer_body() ->
  reset_web_runtime(),
  PrevTrap = process_flag(trap_exit, true),
  try
    {ok, QPid} = openagentic_web_q:start_link(),
    Parent = self(),
    Qid = <<"q_dup_1">>,
    AskPid = spawn(fun () ->
      Answer = openagentic_web_q:ask(<<"wf_1">>, #{question_id => Qid, prompt => <<"Allow?">>, choices => [<<"yes">>, <<"no">>]}),
      Parent ! {ask_answer, Answer}
    end),
    timer:sleep(50),
    ok = openagentic_web_q:answer(Qid, <<"yes">>),
    receive
      {ask_answer, <<"yes">>} -> ok
    after 5000 ->
      ?assert(false)
    end,
    ok = openagentic_web_q:answer(Qid, <<"yes">>),
    timer:sleep(100),
    ?assert(is_process_alive(QPid)),
    ?assert(is_process_alive(AskPid) =:= false)
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

write_web_workflow(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "aggregate.md"]), <<"# aggregate prompt\n">>),
  Json =
    openagentic_json:encode(
      #{
        workflow_version => <<"1.0">>,
        name => <<"web_runtime">>,
        steps => [
          #{
            id => <<"aggregate">>,
            role => <<"shangshu">>,
            input => #{type => <<"controller_input">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/aggregate.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Summary">>]},
            guards => [],
            on_pass => null,
            on_fail => null,
            max_attempts => 1,
            timeout_seconds => 30
          }
        ]
      }
    ),
  write_file(filename:join([Root, "workflows", "w_web.json"]), <<Json/binary, "\n">>).

find_last_workflow_done(Events0, Status) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case {maps:get(<<"type">>, E, <<>>), maps:get(<<"status">>, E, <<>>)} of
        {<<"workflow.done">>, Status} -> E;
        _ -> Best0
      end
    end,
    false,
    Events
  ).

wait_until(Fun, TimeoutMs) ->
  wait_until(Fun, TimeoutMs, erlang:monotonic_time(millisecond)).

wait_until(Fun, TimeoutMs, StartedAt) ->
  case Fun() of
    false ->
      Now = erlang:monotonic_time(millisecond),
      case (Now - StartedAt) >= TimeoutMs of
        true -> ?assert(false);
        false ->
          timer:sleep(100),
          wait_until(Fun, TimeoutMs, StartedAt)
      end;
    undefined ->
      Now = erlang:monotonic_time(millisecond),
      case (Now - StartedAt) >= TimeoutMs of
        true -> ?assert(false);
        false ->
          timer:sleep(100),
          wait_until(Fun, TimeoutMs, StartedAt)
      end;
    Value ->
      Value
  end.

reset_web_runtime() ->
  openagentic_web:stop(),
  maybe_kill(whereis(openagentic_web_runtime_keeper)),
  maybe_kill(whereis(openagentic_web_runtime_sup)),
  maybe_kill(whereis(openagentic_workflow_mgr)),
  maybe_kill(whereis(openagentic_web_q)),
  timer:sleep(100),
  ok.

maybe_kill(Pid) when is_pid(Pid) ->
  catch exit(Pid, kill),
  ok;
maybe_kill(_) ->
  ok.

ensure_httpc_started() ->
  _ = inets:start(),
  case inets:start(httpc) of
    {ok, _Pid} -> ok;
    {error, {already_started, _Pid}} -> ok;
    _ -> ok
  end.

http_post_json(Url0, Body0) ->
  Url = ensure_list(Url0),
  Body = openagentic_json:encode_safe(ensure_map(Body0)),
  Headers = [{"content-type", "application/json"}, {"accept", "application/json"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} =
    httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Opts),
  {Status, openagentic_json:decode(RespBody)}.

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([ensure_list(Cwd), ".tmp", "eunit", "openagentic_web_runtime_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

pick_port() ->
  case gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}, binary, {active, false}]) of
    {ok, Sock} ->
      {ok, {_Ip, Port}} = inet:sockname(Sock),
      ok = gen_tcp:close(Sock),
      Port;
    _ ->
      18089
  end.

write_file(Path, Bin) ->
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  file:write_file(Path, Bin).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(undefined) -> [];
ensure_list_value(null) -> [];
ensure_list_value(Other) -> [Other].

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
