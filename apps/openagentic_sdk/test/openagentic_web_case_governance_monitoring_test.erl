-module(openagentic_web_case_governance_monitoring_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_web_case_governance_test_support, [
  append_round_result/3,
  reset_web_runtime/0,
  maybe_kill/1,
  ensure_httpc_started/0,
  http_post_json/2,
  http_get_json/1,
  http_get_text/1,
  contains_codepoints/2,
  deep_get_bin/2,
  deep_get_int/2,
  tmp_root/0,
  pick_port/0,
  ensure_map/1,
  ensure_list/1,
  to_bin/1
]).

monitoring_run_and_retry_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{
          workflow_session_id => to_bin(Sid),
          title => <<"Iran Situation">>,
          opening_brief => <<"Create a long-running governance case around Iran">>,
          current_summary => <<"Deliberation completed; waiting for candidate extraction">>
        }
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve as monitoring task">>,
          objective => <<"Track diplomatic statement frequency and wording shifts">>
        }
      ),
    TaskId = deep_get_bin(maps:get(<<"task">>, Approved), [<<"header">>, <<"id">>]),

    {201, Failed} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/run",
        #{runtime_opts => #{provider_mod => <<"openagentic_testing_provider_monitoring_invalid">>}}
      ),
    FailedRun = maps:get(<<"run">>, Failed),
    FailedAttempt = maps:get(<<"run_attempt">>, Failed),
    RunId = deep_get_bin(FailedRun, [<<"header">>, <<"id">>]),

    ?assertEqual(<<"failed">>, deep_get_bin(FailedRun, [<<"state">>, <<"status">>])),
    ?assertEqual(<<"failed">>, deep_get_bin(FailedAttempt, [<<"state">>, <<"status">>])),
    ?assertEqual(<<"report_quality_insufficient">>, deep_get_bin(FailedAttempt, [<<"state">>, <<"failure_class">>])),

    {200, Retried} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/runs/" ++ ensure_list(RunId) ++ "/retry",
        #{runtime_opts => #{provider_mod => <<"openagentic_testing_provider_monitoring_success">>}}
      ),
    RetriedRun = maps:get(<<"run">>, Retried),
    RetriedAttempt = maps:get(<<"run_attempt">>, Retried),

    ?assertEqual(<<"report_submitted">>, deep_get_bin(RetriedRun, [<<"state">>, <<"status">>])),
    ?assertEqual(2, deep_get_int(RetriedRun, [<<"state">>, <<"attempt_count">>])),
    ?assertEqual(deep_get_bin(FailedAttempt, [<<"header">>, <<"id">>]), deep_get_bin(RetriedAttempt, [<<"links">>, <<"previous_attempt_id">>])),
    ?assert(maps:is_key(<<"fact_report">>, Retried)),

    {200, Detail} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    ?assertEqual(1, length(maps:get(<<"runs">>, Detail))),
    ?assertEqual(2, length(maps:get(<<"run_attempts">>, Detail))),
    ?assertEqual(1, length(maps:get(<<"fact_reports">>, Detail))),
    ?assert(length(maps:get(<<"artifacts">>, Detail)) >= 3),
    [DetailRun | _] = maps:get(<<"runs">>, Detail),
    [DetailReport | _] = maps:get(<<"fact_reports">>, Detail),
    ?assertEqual(2, deep_get_int(DetailRun, [<<"state">>, <<"attempt_count">>])),
    ?assertEqual(<<"submitted">>, deep_get_bin(DetailReport, [<<"state">>, <<"status">>])),
    ?assert(deep_get_bin(DetailReport, [<<"ext">>, <<"report_lineage_id">>]) =/= <<>>)
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

