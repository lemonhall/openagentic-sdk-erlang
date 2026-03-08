-module(openagentic_case_store_run_delivery_test).

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

run_task_rejects_delivery_that_violates_report_contract_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} =
    create_active_task_fixture(
      Root,
      #{report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}}
    ),

  {ok, Res} =
    openagentic_case_store:run_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_contract_invalid}
      }
    ),

  Run = maps:get(run, Res),
  Attempt = maps:get(run_attempt, Res),
  ?assertEqual(<<"failed">>, deep_get(Run, [state, status])),
  ?assertEqual(<<"report_contract_rejected">>, deep_get(Attempt, [state, failure_class])),
  ?assert(not maps:is_key(fact_report, Res)),
  ?assert(maps:is_key(mail, Res)),
  ?assert(maps:is_key(exception_brief, Res)),
  ok.

failed_run_creates_exception_brief_mail_and_failure_stats_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} = create_active_task_fixture(Root),

  {ok, Res} =
    openagentic_case_store:run_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_auth_expired}
      }
    ),

  Attempt = maps:get(run_attempt, Res),
  Mail = maps:get(mail, Res),
  Brief = maps:get(exception_brief, Res),
  ?assertEqual(<<"auth_expired">>, deep_get(Attempt, [state, failure_class])),
  ?assertEqual(<<"task_run_failed">>, deep_get(Mail, [spec, message_type])),
  ?assertEqual(<<"task_exception_brief">>, deep_get(Brief, [spec, briefing_kind])),
  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  FailureStats = maps:get(failure_stats, Detail),
  ?assertEqual(1, deep_get(FailureStats, [by_class, <<"auth_expired">>])),
  ?assertEqual(1, length(maps:get(exception_briefs, Detail))),
  ok.

