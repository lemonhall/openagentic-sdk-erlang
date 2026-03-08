-module(openagentic_web_case_governance_reauth_hint_test).

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

task_detail_api_exposes_reauthorization_hint_after_revision_test() ->
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
    {ok, _} =
      openagentic_web:start(
        #{
          project_dir => Root,
          session_root => Root,
          web_bind => "127.0.0.1",
          web_port => Port,
          provider_mod => openagentic_testing_provider,
          tools => [openagentic_tool_echo],
          permission_mode_override => bypass,
          api_key => <<"x">>,
          model => <<"x">>
        }
      ),
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

    {201, _Revised} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/revise",
        #{
          governance_session_id => GovernanceSid,
          revised_by_op_id => <<"lemon">>,
          change_summary => <<"Add credential-gated source access">>,
          objective => <<"Track diplomatic statement shifts with credential-gated source access">>,
          credential_requirements =>
            #{
              required_slots =>
                [
                  #{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}
                ]
            }
        }
      ),

    {200, Detail} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    Diff = maps:get(<<"latest_version_diff">>, Detail),
    ?assertEqual(<<"reauthorization_required">>, deep_get_bin(Detail, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(true, maps:get(<<"reauthorization_required">>, Diff)),
    ?assertEqual([<<"x_session">>], maps:get(<<"newly_required_slots">>, Diff)),
    ?assertEqual(<<"reauthorization_required">>, maps:get(<<"authorization_status">>, Diff)),

    {201, Bound} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/credential-bindings",
        #
        {
          slot_name => <<"x_session">>,
          binding_type => <<"cookie">>,
          provider => <<"x">>,
          material_ref => <<"secure://materials/x-session-cookie">>,
          status => <<"validated">>
        }
      ),
    ?assertEqual(<<"ready_to_activate">>, deep_get_bin(Bound, [<<"task">>, <<"state">>, <<"status">>])),

    {200, _Activated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/activate",
        #{activated_by_op_id => <<"lemon">>}
      ),
    {200, Detail2} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    Diff2 = maps:get(<<"latest_version_diff">>, Detail2),
    ?assertEqual(<<"active">>, deep_get_bin(Detail2, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(false, maps:get(<<"reauthorization_required">>, Diff2)),
    ?assertEqual(<<"active">>, maps:get(<<"authorization_status">>, Diff2))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

