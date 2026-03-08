-module(openagentic_case_store_approve_test).

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

approve_candidate_promotes_review_session_to_governance_session_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),
  CandidateId = id_of(Candidate),
  ReviewSid = deep_get(Candidate, [links, review_session_id]),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => CandidateId,
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"Approve as monitoring task">>,
        objective => <<"Track diplomatic statement frequency, wording, and topic shifts">>,
        schedule_policy => #{mode => <<"interval">>, interval => #{value => 6, unit => <<"hours">>}},
        report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]},
        alert_rules => #{severity_threshold => <<"high">>},
        source_strategy => #{primary => [<<"official">>, <<"media">>]},
        tool_profile => #{allowed_tools => [<<"WebFetch">>, <<"Bash">>]},
        autonomy_policy => #{mode => <<"unattended">>},
        promotion_policy => #{publish_to_case => false}
      }
    ),

  Task = maps:get(task, Approved),
  Version = maps:get(task_version, Approved),
  TaskId = id_of(Task),
  Overview = maps:get(overview, Approved),
  WorkspaceRef = deep_get(Task, [links, workspace_ref]),
  TaskWorkspace = filename:join([Root, "cases", ensure_list(CaseId), ensure_list(WorkspaceRef)]),

  ?assertEqual(ReviewSid, deep_get(Task, [links, governance_session_id])),
  ?assertEqual(id_of(Version), deep_get(Task, [links, active_version_id])),
  ?assertEqual(<<"approved">>, deep_get(maps:get(candidate, Approved), [state, status])),
  ?assertEqual(<<"active">>, deep_get(Task, [state, status])),
  ?assertEqual(<<"active">>, deep_get(Version, [state, status])),
  ?assert(filelib:is_dir(TaskWorkspace)),
  ?assert(filelib:is_file(filename:join([TaskWorkspace, "TASK.md"]))),
  OverviewCase = maps:get('case', Overview),
  ?assertEqual(1, maps:get(active_task_count, maps:get(state, OverviewCase))),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= TaskId end, maps:get(tasks, Overview))),
  ok.

approve_candidate_with_credential_requirements_enters_authorization_flow_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),
  CandidateId = id_of(Candidate),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => CandidateId,
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

  Task0 = maps:get(task, Approved),
  TaskId = id_of(Task0),
  Overview0 = maps:get(overview, Approved),
  OverviewCase0 = maps:get('case', Overview0),
  ?assertEqual(<<"awaiting_credentials">>, deep_get(Task0, [state, status])),
  ?assertEqual([], deep_get(Task0, [spec, credential_binding_refs])),
  ?assertEqual(0, maps:get(active_task_count, maps:get(state, OverviewCase0))),

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

  Binding = maps:get(credential_binding, Bound),
  Task1 = maps:get(task, Bound),
  ?assertEqual(<<"ready_to_activate">>, deep_get(Task1, [state, status])),
  ?assert(lists:member(id_of(Binding), deep_get(Task1, [spec, credential_binding_refs]))),
  ?assertEqual(1, length(maps:get(credential_bindings, Bound))),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Auth = maps:get(authorization, Detail),
  ?assertEqual([<<"x_session">>], maps:get(required_slots, Auth)),
  ?assertEqual([], maps:get(missing_slots, Auth)),
  ?assertEqual(1, length(maps:get(versions, Detail))),
  ?assertEqual(1, length(maps:get(credential_bindings, Detail))),

  {ok, Activated} =
    openagentic_case_store:activate_task(
      Root,
      #{case_id => CaseId, task_id => TaskId, activated_by_op_id => <<"lemon">>}
    ),

  Task2 = maps:get(task, Activated),
  Overview1 = maps:get(overview, Activated),
  OverviewCase1 = maps:get('case', Overview1),
  ?assertEqual(<<"active">>, deep_get(Task2, [state, status])),
  ?assertEqual(1, maps:get(active_task_count, maps:get(state, OverviewCase1))),
  ok.

