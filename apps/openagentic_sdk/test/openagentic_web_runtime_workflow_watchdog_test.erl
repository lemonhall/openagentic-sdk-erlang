-module(openagentic_web_runtime_workflow_watchdog_test).

-include_lib("eunit/include/eunit.hrl").

workflow_watchdog_visibility_and_continue_status_test_() ->
  {timeout, 45, fun workflow_watchdog_visibility_and_continue_status_body/0}.

workflow_watchdog_visibility_and_continue_status_body() ->
  openagentic_web_runtime_test_support:reset_web_runtime(),
  ok = openagentic_web_runtime_test_support:ensure_httpc_started(),
  Root = openagentic_web_runtime_test_support:tmp_root(),
  ok = openagentic_web_runtime_test_support:write_web_workflow(Root),
  Port = openagentic_web_runtime_test_support:pick_port(),
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
  Url = openagentic_web_runtime_test_support:ensure_list(Url0),
  try
    {201, StartResp} = openagentic_web_runtime_test_support:http_post_json(Url ++ "api/workflows/start", #{prompt => <<"hello">>, dsl => <<"workflows/w_web.json">>}),
    WfSid = maps:get(<<"workflow_session_id">>, StartResp),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, StartResp, <<>>)),

    {202, QueuedResp} = openagentic_web_runtime_test_support:http_post_json(Url ++ "api/workflows/continue", #{workflow_session_id => WfSid, message => <<"follow up">>}),
    ?assertEqual(<<"queued">>, maps:get(<<"status">>, QueuedResp, <<>>)),
    ?assertEqual(true, maps:get(<<"queued">>, QueuedResp, false)),

    StalledDone =
      openagentic_web_runtime_test_support:wait_until(
        fun () ->
          Events = openagentic_session_store:read_events(Root, openagentic_web_runtime_test_support:ensure_list(WfSid)),
          openagentic_web_runtime_test_support:find_last_workflow_done(Events, <<"stalled">>)
        end,
        12000
      ),
    ?assertEqual(<<"watchdog">>, maps:get(<<"by">>, StalledDone, <<>>)),

    {ok, StatusResp} = openagentic_workflow_mgr:status(Root, WfSid),
    ?assertEqual(<<"stalled">>, maps:get(status, StatusResp, <<>>)),

    {202, ResumeResp} = openagentic_web_runtime_test_support:http_post_json(Url ++ "api/workflows/continue", #{workflow_session_id => WfSid, message => <<"resume">>}),
    ?assertEqual(<<"resumed_from_stalled">>, maps:get(<<"status">>, ResumeResp, <<>>)),
    ?assertEqual(true, maps:get(<<"resumed_from_stalled">>, ResumeResp, false)),
    ?assertEqual(<<"stalled">>, maps:get(<<"previous_status">>, ResumeResp, <<>>)),

    CompletedDone =
      openagentic_web_runtime_test_support:wait_until(
        fun () ->
          Events = openagentic_session_store:read_events(Root, openagentic_web_runtime_test_support:ensure_list(WfSid)),
          openagentic_web_runtime_test_support:find_last_workflow_done(Events, <<"completed">>)
        end,
        8000
      ),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, CompletedDone, <<>>))
  after
    openagentic_web:stop(),
    ets:delete(Tab),
    openagentic_web_runtime_test_support:reset_web_runtime()
  end,
  ok.
