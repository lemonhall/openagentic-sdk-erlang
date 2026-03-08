-module(openagentic_case_store_monitoring_run_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [
  create_case_fixture/1,
  create_active_task_fixture/1,
  create_active_task_fixture/2,
  append_round_result/3,
  id_of/1,
  deep_get/2,
  tmp_root/0,
  ensure_list/1,
  to_bin/1,
  file_lines/1
]).

run_task_creates_monitoring_run_attempt_and_fact_report_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} = create_active_task_fixture(Root),

  {ok, Res} =
    openagentic_case_store:run_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}
      }
    ),

  Run = maps:get(run, Res),
  Attempt = maps:get(run_attempt, Res),
  Report = maps:get(fact_report, Res),
  CaseDir = filename:join([Root, "cases", ensure_list(CaseId)]),
  ScratchDir = filename:join([CaseDir, ensure_list(deep_get(Attempt, [links, scratch_ref]))]),
  ExecSid = deep_get(Attempt, [links, execution_session_id]),

  ?assertEqual(<<"report_submitted">>, deep_get(Run, [state, status])),
  ?assertEqual(1, deep_get(Run, [state, attempt_count])),
  ?assertEqual(<<"succeeded">>, deep_get(Attempt, [state, status])),
  ?assertEqual(<<"submitted">>, deep_get(Report, [state, status])),
  ?assert(filelib:is_dir(ScratchDir)),
  ?assert(filelib:is_file(filename:join([ScratchDir, "report.md"]))),
  ?assert(filelib:is_file(filename:join([ScratchDir, "facts.json"]))),
  ?assert(filelib:is_file(filename:join([ScratchDir, "artifacts.json"]))),
  ?assert(filelib:is_dir(openagentic_session_store:session_dir(Root, ensure_list(ExecSid)))),
  ?assert(
    lists:any(
      fun (Event) -> maps:get(<<"type">>, Event, <<>>) =:= <<"result">> end,
      openagentic_session_store:read_events(Root, ensure_list(ExecSid))
    )
  ),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  ?assertEqual(1, length(maps:get(runs, Detail))),
  ?assertEqual(1, length(maps:get(run_attempts, Detail))),
  ?assertEqual(1, length(maps:get(fact_reports, Detail))),
  ?assert(length(maps:get(artifacts, Detail)) >= 3),
  ok.

scheduled_interval_task_run_once_creates_due_run_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} =
    create_active_task_fixture(
      Root,
      #{
        schedule_policy => #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 1, unit => <<"hours">>}},
        report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}
      }
    ),

  {ok, RunRes} =
    openagentic_case_scheduler:run_once(
      #{
        session_root => Root,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}
      }
    ),

  ?assertEqual(1, maps:get(triggered_run_count, RunRes)),
  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  [Run] = maps:get(runs, Detail),
  [Attempt] = maps:get(run_attempts, Detail),
  [Report] = maps:get(fact_reports, Detail),
  ?assertEqual(<<"scheduled">>, deep_get(Run, [spec, run_kind])),
  ?assertEqual(<<"schedule_policy">>, deep_get(Run, [spec, trigger_type])),
  ?assertEqual(<<"report_submitted">>, deep_get(Run, [state, status])),
  ?assertEqual(<<"succeeded">>, deep_get(Attempt, [state, status])),
  ?assertEqual(<<"submitted">>, deep_get(Report, [state, status])),
  ok.

