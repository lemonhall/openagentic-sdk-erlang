-module(openagentic_web_case_governance_task_detail_test).

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

task_detail_and_credential_binding_api_test() ->
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
          approval_summary => <<"Approve pending credentials">>,
          objective => <<"Track diplomatic statement frequency, wording, and topic shifts">>,
          credential_requirements =>
            #{
              required_slots =>
                [
                  #{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}
                ]
            }
        }
      ),
    TaskId = deep_get_bin(maps:get(<<"task">>, Approved), [<<"header">>, <<"id">>]),
    ?assertEqual(<<"awaiting_credentials">>, deep_get_bin(maps:get(<<"task">>, Approved), [<<"state">>, <<"status">>])),

    {200, TaskDetailHtml} =
      http_get_text(
        Base ++ "view/task-detail.html?case_id=" ++ ensure_list(CaseId) ++ "&task_id=" ++ ensure_list(TaskId)
      ),
    ?assert(string:find(TaskDetailHtml, "taskDetailView") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "credentialBindingForm") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "taskVersions") =/= nomatch),

    {200, Detail0} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    ?assertEqual(<<"awaiting_credentials">>, deep_get_bin(Detail0, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(1, length(maps:get(<<"required_slots">>, maps:get(<<"authorization">>, Detail0)))),
    ?assertEqual(0, length(maps:get(<<"credential_bindings">>, Detail0))),

    {201, Bound} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/credential-bindings",
        #{
          slot_name => <<"x_session">>,
          binding_type => <<"cookie">>,
          provider => <<"x">>,
          material_ref => <<"secure://materials/x-session-cookie">>,
          status => <<"validated">>
        }
      ),
    ?assertEqual(<<"ready_to_activate">>, deep_get_bin(Bound, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(1, length(maps:get(<<"credential_bindings">>, Bound))),

    {200, Activated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/activate",
        #{activated_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"active">>, deep_get_bin(Activated, [<<"task">>, <<"state">>, <<"status">>]))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

