-module(openagentic_web_case_governance_task_revision_test).

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

task_revision_api_updates_task_detail_versions_test() ->
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
    Task = maps:get(<<"task">>, Approved),
    TaskId = deep_get_bin(Task, [<<"header">>, <<"id">>]),
    GovernanceSid = deep_get_bin(Task, [<<"links">>, <<"governance_session_id">>]),

    {201, Revised} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/revise",
        #{
          governance_session_id => GovernanceSid,
          revised_by_op_id => <<"lemon">>,
          change_summary => <<"Narrow focus to escalation risk">>,
          objective => <<"Track diplomatic statement shifts with emphasis on escalation risk">>
        }
      ),
    NewVersionId = deep_get_bin(maps:get(<<"task_version">>, Revised), [<<"header">>, <<"id">>]),

    {200, Detail} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    Versions = maps:get(<<"versions">>, Detail),
    ?assertEqual(2, length(Versions)),
    ?assertEqual(NewVersionId, deep_get_bin(maps:get(<<"task">>, Detail), [<<"links">>, <<"active_version_id">>])),
    ?assertEqual(<<"superseded">>, deep_get_bin(lists:nth(1, Versions), [<<"state">>, <<"status">>])),
    ?assertEqual(<<"active">>, deep_get_bin(lists:nth(2, Versions), [<<"state">>, <<"status">>])),
    Diff0 = maps:get(<<"latest_version_diff">>, Detail),
    ?assertEqual(<<"Narrow focus to escalation risk">>, maps:get(<<"change_summary">>, Diff0)),
    ?assertEqual(false, maps:get(<<"reauthorization_required">>, Diff0))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

