-module(openagentic_case_store_test).

-include_lib("eunit/include/eunit.hrl").

create_case_from_round_persists_case_and_round_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok = append_round_result(Root, Sid, <<"## Deliberation Summary\n- Keep watching the regional situation\n">>),

  {ok, Res} =
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>,
        opening_brief => <<"Create a long-running governance case around Iran">>,
        current_summary => <<"Deliberation completed; waiting for candidate extraction">>,
        topic => <<"geopolitics">>,
        owner => <<"lemon">>,
        default_timezone => <<"Asia/Shanghai">>
      }
    ),

  CaseObj = maps:get('case', Res),
  RoundObj = maps:get(round, Res),
  CaseId = id_of(CaseObj),
  RoundId = id_of(RoundObj),
  CaseDir = filename:join([Root, "cases", ensure_list(CaseId)]),

  ?assert(filelib:is_dir(filename:join([CaseDir, "meta"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "artifacts"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "workspaces"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "published"]))),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "case.json"]))),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "rounds", ensure_list(<<RoundId/binary, ".json">>)]))),
  ?assertEqual(to_bin(Sid), deep_get(CaseObj, [links, origin_workflow_session_id])),
  ?assertEqual(to_bin(Sid), deep_get(RoundObj, [links, workflow_session_id])),
  ok.

create_case_from_round_requires_completed_workflow_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),

  ?assertEqual(
    {error, workflow_session_not_completed},
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>
      }
    )
  ),
  ok.

create_case_from_round_auto_extracts_candidates_by_default_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok =
    append_round_result(
      Root,
      Sid,
      <<"## Suggested Monitoring Items\n",
        "- Monitor Iran diplomatic statement frequency and wording shifts\n",
        "- Track US sanctions policy and enforcement cadence\n">>
    ),

  {ok, Res} =
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>,
        opening_brief => <<"Create a long-running governance case around Iran">>,
        current_summary => <<"Deliberation completed; waiting for candidate extraction">>
      }
    ),

  Candidates = maps:get(candidates, Res),
  Mail = maps:get(mail, Res),
  Overview = maps:get(overview, Res),
  OverviewCase = maps:get('case', Overview),
  ?assertEqual(2, length(Candidates)),
  ?assertEqual(2, length(Mail)),
  ?assertEqual(<<"post_deliberation_extraction">>, deep_get(OverviewCase, [state, phase])),
  ok.

extract_candidates_from_round_creates_inbox_candidates_and_mail_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),

  {ok, Res} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),

  Candidates = maps:get(candidates, Res),
  Mail = maps:get(mail, Res),
  ?assertEqual(2, length(Candidates)),
  ?assertEqual(2, length(Mail)),
  lists:foreach(
    fun (Candidate) ->
      ReviewSid = deep_get(Candidate, [links, review_session_id]),
      ?assertEqual(<<"inbox_pending">>, deep_get(Candidate, [state, status])),
      ?assert(byte_size(ReviewSid) > 0),
      ?assert(filelib:is_dir(openagentic_session_store:session_dir(Root, ensure_list(ReviewSid))))
    end,
    Candidates
  ),
  ok.

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
  ?assertEqual(<<"awaiting_credentials">>, deep_get(Task1, [state, status])),
  ?assertEqual([<<"x_session">>], maps:get(missing_slots, Auth1)),

  {ok, Detail} = openagentic_case_store:get_task_detail(Root, CaseId, TaskId),
  Diff = maps:get(latest_version_diff, Detail),
  ChangedFields = maps:get(changed_fields, Diff),
  ?assertEqual(true, maps:get(credential_requirements_changed, Diff)),
  ?assertEqual(true, maps:get(reauthorization_required, Diff)),
  ?assertEqual([<<"x_session">>], maps:get(newly_required_slots, Diff)),
  ?assertEqual(<<"awaiting_credentials">>, maps:get(authorization_status, Diff)),
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
  ok.

discard_candidate_marks_candidate_discarded_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [_First, Candidate] = maps:get(candidates, Extracted),

  {ok, Discarded} =
    openagentic_case_store:discard_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => id_of(Candidate),
        reason => <<"Out of scope for this case">>,
        acted_by_op_id => <<"lemon">>
      }
    ),

  ?assertEqual(<<"discarded">>, deep_get(Discarded, [state, status])),
  ok.

create_case_fixture(Root) ->
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok =
    append_round_result(
      Root,
      Sid,
      <<"## Suggested Monitoring Items\n",
        "- Monitor Iran diplomatic statement frequency and wording shifts\n",
        "- Track US sanctions policy and enforcement cadence\n">>
    ),
  {ok, Created} =
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>,
        opening_brief => <<"Create a long-running governance case around Iran">>,
        current_summary => <<"Deliberation completed; waiting for candidate extraction">>,
        topic => <<"geopolitics">>,
        owner => <<"lemon">>,
        default_timezone => <<"Asia/Shanghai">>
      }
    ),
  {id_of(maps:get('case', Created)), id_of(maps:get(round, Created)), Sid}.

append_round_result(Root, Sid, FinalText) ->
  {ok, _} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:workflow_done(<<"wf_case">>, <<"governance">>, <<"completed">>, FinalText, #{})
    ),
  ok.

id_of(Obj) -> deep_get(Obj, [header, id]).

deep_get(Obj, [Key]) -> maps:get(Key, Obj);
deep_get(Obj, [Key | Rest]) -> deep_get(maps:get(Key, Obj), Rest).

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_case_store_test", Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
