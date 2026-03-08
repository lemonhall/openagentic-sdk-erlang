-module(openagentic_web_e2e_online_smoke_test).

-include_lib("eunit/include/eunit.hrl").

web_e2e_online_test_() ->
  case openagentic_web_e2e_online_test_support:should_run() of
    {skip, _Why} ->
      [];
    {ok, Cfg} ->
      {timeout, 300, fun () -> run_e2e(Cfg) end}
  end.

%% ---- e2e ----

run_e2e(Cfg) ->
  ProjectDir = maps:get(project_dir, Cfg),
  Root = maps:get(session_root, Cfg),
  Port = maps:get(port, Cfg),
  Opts = maps:get(runtime_opts, Cfg),

  ok = openagentic_web_e2e_online_test_support:ensure_httpc_started(),
  {ok, #{url := Url0}} = openagentic_web:start(Opts#{project_dir => ProjectDir, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
  Url = openagentic_web_e2e_online_test_support:ensure_list(Url0),

  try
    StartUrl = Url ++ "api/workflows/start",
    Body = #{prompt => <<"hello e2e">>, dsl => <<"workflows/e2e-web-online.v1.json">>},
    {201, StartResp} = openagentic_web_e2e_online_test_support:http_post_json(StartUrl, Body),
    SidBin = maps:get(<<"workflow_session_id">>, StartResp),
    Sid = openagentic_web_e2e_online_test_support:ensure_list(SidBin),

    %% Subscribe to SSE and wait for workflow.done.
    EventsUrl = Url ++ "api/sessions/" ++ Sid ++ "/events",
    {ok, _ReqId} = openagentic_web_e2e_online_sse_support:sse_wait_done(EventsUrl, 240000)
  after
    _ = openagentic_web:stop(),
    ok
  end,
  ok.

%% ---- SSE client ----
