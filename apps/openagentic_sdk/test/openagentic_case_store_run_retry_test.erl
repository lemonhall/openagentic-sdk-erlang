-module(openagentic_case_store_run_retry_test).

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

retry_run_adds_second_attempt_after_failure_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} = create_active_task_fixture(Root),

  {ok, Failed0} =
    openagentic_case_store:run_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_invalid}
      }
    ),
  FailedRun = maps:get(run, Failed0),
  FailedAttempt = maps:get(run_attempt, Failed0),
  RunId = id_of(FailedRun),

  ?assertEqual(<<"failed">>, deep_get(FailedRun, [state, status])),
  ?assertEqual(<<"failed">>, deep_get(FailedAttempt, [state, status])),
  ?assertEqual(<<"report_quality_insufficient">>, deep_get(FailedAttempt, [state, failure_class])),
  ?assert(not maps:is_key(fact_report, Failed0)),

  {ok, Retried} =
    openagentic_case_store:retry_run(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        run_id => RunId,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}
      }
    ),

  RetriedRun = maps:get(run, Retried),
  RetriedAttempt = maps:get(run_attempt, Retried),
  ?assertEqual(<<"report_submitted">>, deep_get(RetriedRun, [state, status])),
  ?assertEqual(2, deep_get(RetriedRun, [state, attempt_count])),
  ?assertEqual(id_of(FailedAttempt), deep_get(RetriedAttempt, [links, previous_attempt_id])),
  ?assertEqual(id_of(RetriedAttempt), deep_get(RetriedRun, [links, successful_attempt_id])),
  ?assert(maps:is_key(fact_report, Retried)),
  ok.

repeated_failed_runs_mark_task_rectification_required_and_create_mail_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} = create_active_task_fixture(Root),

  lists:foreach(
    fun (_) ->
      {ok, _} =
        openagentic_case_store:run_task(
          Root,
          #{
            case_id => CaseId,
            task_id => TaskId,
            runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_invalid}
          }
        )
    end,
    lists:seq(1, 3)
  ),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Task = maps:get(task, Detail),
  ?assertEqual(<<"rectification_required">>, deep_get(Task, [state, status])),
  ?assertEqual(<<"rectification_required">>, deep_get(Task, [state, health])),

  {ok, Overview} = openagentic_case_store:get_case_overview(Root, CaseId),
  Mail = maps:get(mail, Overview),
  ?assert(
    lists:any(
      fun (MailObj) -> deep_get(MailObj, [spec, message_type]) =:= <<"task_rectification_required">> end,
      Mail
    )
  ),
  ok.

