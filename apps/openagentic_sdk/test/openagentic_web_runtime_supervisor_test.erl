-module(openagentic_web_runtime_supervisor_test).

-include_lib("eunit/include/eunit.hrl").

web_runtime_supervisor_isolates_caller_from_internal_service_crash_test_() ->
  {timeout, 30, fun web_runtime_supervisor_isolates_caller_from_internal_service_crash_body/0}.

web_runtime_supervisor_isolates_caller_from_internal_service_crash_body() ->
  openagentic_web_runtime_test_support:reset_web_runtime(),
  Root = openagentic_web_runtime_test_support:tmp_root(),
  Port = openagentic_web_runtime_test_support:pick_port(),
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
  ServicePid = openagentic_web_runtime_test_support:wait_until(fun () -> whereis(openagentic_web_q) end, 5000),
  ?assert(is_pid(ServicePid)),
  exit(ServicePid, kill),
  RestartedServicePid =
    openagentic_web_runtime_test_support:wait_until(
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
  openagentic_web_runtime_test_support:reset_web_runtime(),
  ok.
