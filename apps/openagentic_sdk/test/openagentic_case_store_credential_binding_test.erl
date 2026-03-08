-module(openagentic_case_store_credential_binding_test).

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

credential_binding_rotation_and_invalidation_test() ->
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
        approval_summary => <<"Approve pending credentials">>,
        objective => <<"Track diplomatic statement frequency and wording shifts">>,
        credential_requirements =>
          #{required_slots => [#{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}]} 
      }
    ),
  Task0 = maps:get(task, Approved),
  TaskId = id_of(Task0),

  {ok, Bound0} =
    openagentic_case_store:upsert_credential_binding(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        slot_name => <<"x_session">>,
        binding_type => <<"cookie">>,
        provider => <<"x">>,
        material_ref => <<"secure://materials/x-session-cookie-v1">>,
        status => <<"validated">>
      }
    ),
  Binding0 = maps:get(credential_binding, Bound0),

  {ok, _Activated} =
    openagentic_case_store:activate_task(
      Root,
      #{case_id => CaseId, task_id => TaskId, activated_by_op_id => <<"lemon">>}
    ),

  {ok, Rotated} =
    openagentic_case_store:upsert_credential_binding(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        rotate_binding_id => id_of(Binding0),
        acted_by_op_id => <<"lemon">>,
        note => <<"Rotate compromised session cookie">>,
        material_ref => <<"secure://materials/x-session-cookie-v2">>
      }
    ),
  Binding1 = maps:get(credential_binding, Rotated),
  Bindings1 = maps:get(credential_bindings, Rotated),
  [RotatedOld] = [B || B <- Bindings1, id_of(B) =:= id_of(Binding0)],
  ?assert(id_of(Binding1) =/= id_of(Binding0)),
  ?assertEqual(<<"rotated">>, deep_get(RotatedOld, [state, status])),
  ?assertEqual(id_of(Binding1), deep_get(RotatedOld, [links, rotated_to_binding_id])),
  ?assertEqual(id_of(Binding0), deep_get(Binding1, [links, rotated_from_binding_id])),
  ?assertEqual(<<"active">>, deep_get(maps:get(task, Rotated), [state, status])),

  {ok, Invalidated} =
    openagentic_case_store:invalidate_credential_binding(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        credential_binding_id => id_of(Binding1),
        status => <<"revoked">>,
        acted_by_op_id => <<"lemon">>,
        reason => <<"Provider revoked the session">>
      }
    ),
  ?assertEqual(<<"revoked">>, deep_get(maps:get(credential_binding, Invalidated), [state, status])),
  ?assertEqual(<<"reauthorization_required">>, deep_get(maps:get(task, Invalidated), [state, status])),
  ?assertEqual(<<"reauthorization_required">>, maps:get(status, maps:get(authorization, Invalidated))),
  ok.

