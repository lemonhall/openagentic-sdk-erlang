-module(openagentic_case_store_task_reauth_test).

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

revise_task_with_new_credentials_requires_reauthorization_and_exposes_diff_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => id_of(Candidate),
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"Approve as monitoring task">>,
        objective => <<"Track diplomatic statement frequency and wording shifts">>
      }
    ),

  Task0 = maps:get(task, Approved),
  TaskId = id_of(Task0),
  GovernanceSid = deep_get(Task0, [links, governance_session_id]),

  {ok, Revised} =
    openagentic_case_store:revise_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
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

  Task1 = maps:get(task, Revised),
  Auth1 = maps:get(authorization, Revised),
  ?assertEqual(<<"reauthorization_required">>, deep_get(Task1, [state, status])),
  ?assertEqual([<<"x_session">>], maps:get(missing_slots, Auth1)),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Diff = maps:get(latest_version_diff, Detail),
  ChangedFields = maps:get(changed_fields, Diff),
  ?assertEqual(true, maps:get(credential_requirements_changed, Diff)),
  ?assertEqual(true, maps:get(reauthorization_required, Diff)),
  ?assertEqual([<<"x_session">>], maps:get(newly_required_slots, Diff)),
  ?assertEqual(<<"reauthorization_required">>, maps:get(authorization_status, Diff)),
  ?assert(
    lists:any(
      fun (Item) -> maps:get(field, Item) =:= <<"objective">> end,
      ChangedFields
    )
  ),
  ?assert(
    lists:any(
      fun (Item) -> maps:get(field, Item) =:= <<"credential_requirements">> end,
      ChangedFields
    )
  ),

  {ok, Bound} =
    openagentic_case_store:upsert_credential_binding(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        slot_name => <<"x_session">>,
        binding_type => <<"cookie">>,
        provider => <<"x">>,
        material_ref => <<"secure://materials/x-session-cookie">>,
        status => <<"validated">>
      }
    ),
  Task2 = maps:get(task, Bound),
  ?assertEqual(<<"ready_to_activate">>, deep_get(Task2, [state, status])),

  {ok, Detail1} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Diff1 = maps:get(latest_version_diff, Detail1),
  ?assertEqual(true, maps:get(reauthorization_required, Diff1)),
  ?assertEqual(<<"ready_to_activate">>, maps:get(authorization_status, Diff1)),

  {ok, Activated} =
    openagentic_case_store:activate_task(
      Root,
      #{case_id => CaseId, task_id => TaskId, activated_by_op_id => <<"lemon">>}
    ),
  Task3 = maps:get(task, Activated),
  ?assertEqual(<<"active">>, deep_get(Task3, [state, status])),

  {ok, Detail2} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Diff2 = maps:get(latest_version_diff, Detail2),
  ?assertEqual(false, maps:get(reauthorization_required, Diff2)),
  ?assertEqual(<<"active">>, maps:get(authorization_status, Diff2)),
  ok.

