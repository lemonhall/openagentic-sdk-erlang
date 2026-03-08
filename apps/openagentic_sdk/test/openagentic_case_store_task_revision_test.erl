-module(openagentic_case_store_task_revision_test).

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

revise_task_creates_new_active_version_on_same_governance_session_test() ->
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
  OldVersion = maps:get(task_version, Approved),
  TaskId = id_of(Task0),
  GovernanceSid = deep_get(Task0, [links, governance_session_id]),
  OldVersionId = id_of(OldVersion),

  {ok, Revised} =
    openagentic_case_store:revise_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        governance_session_id => GovernanceSid,
        revised_by_op_id => <<"lemon">>,
        change_summary => <<"Narrow focus to escalation risk">>,
        objective => <<"Track diplomatic statement shifts with emphasis on escalation risk">>
      }
    ),

  Task1 = maps:get(task, Revised),
  Version1 = maps:get(task_version, Revised),
  Version1Id = id_of(Version1),
  ?assert(Version1Id =/= OldVersionId),
  ?assertEqual(OldVersionId, deep_get(Version1, [links, previous_version_id])),
  ?assertEqual(Version1Id, deep_get(Task1, [links, active_version_id])),
  ?assertEqual(<<"active">>, deep_get(Version1, [state, status])),
  ?assertEqual(<<"Track diplomatic statement shifts with emphasis on escalation risk">>, deep_get(Version1, [spec, objective])),
  ?assertEqual(<<"Narrow focus to escalation risk">>, deep_get(Version1, [audit, change_summary])),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Versions = maps:get(versions, Detail),
  ?assertEqual(2, length(Versions)),
  [Version0After, Version1After] = Versions,
  ?assertEqual(OldVersionId, id_of(Version0After)),
  ?assertEqual(<<"superseded">>, deep_get(Version0After, [state, status])),
  ?assertEqual(Version1Id, id_of(Version1After)),
  ?assertEqual(<<"active">>, deep_get(Version1After, [state, status])),
  ok.

