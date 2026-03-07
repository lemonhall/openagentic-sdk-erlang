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

template_library_instantiation_and_history_registry_test() ->
  Root = tmp_root(),
  {CaseId, _RoundId, _Sid} = create_case_fixture(Root),

  {ok, CreatedTemplate} =
    openagentic_case_store:create_template(
      Root,
      #{
        case_id => CaseId,
        created_by_op_id => <<"lemon">>,
        title => <<"外交表态监测模板">>,
        summary => <<"适用于外交表态频率、措辞与升级风险监测">>,
        objective => <<"Track diplomatic statement shifts with escalation risk emphasis">>,
        template_body => <<"# Template\n\nReference fetch + parse scaffold\n">>,
        credential_requirements => #{required_slots => [#{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}]} 
      }
    ),
  Template = maps:get(template, CreatedTemplate),
  TemplateId = id_of(Template),

  {ok, Templates} = openagentic_case_store:list_templates(Root, CaseId),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= TemplateId end, Templates)),

  {ok, Instantiated} =
    openagentic_case_store:instantiate_template_candidate(
      Root,
      #{case_id => CaseId, template_id => TemplateId, acted_by_op_id => <<"lemon">>}
    ),
  Candidate = maps:get(candidate, Instantiated),
  ?assertEqual(TemplateId, deep_get(Candidate, [spec, template_ref])),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => id_of(Candidate),
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"Instantiate from template">>
      }
    ),
  Task = maps:get(task, Approved),
  Version = maps:get(task_version, Approved),
  CaseDir = filename:join([Root, "cases", ensure_list(CaseId)]),
  RegistryPath = filename:join([CaseDir, "meta", "object-type-registry.json"]),
  CaseHistoryPath = filename:join([CaseDir, "meta", "history.jsonl"]),
  TaskHistoryPath = filename:join([CaseDir, "meta", "tasks", ensure_list(id_of(Task)), "history.jsonl"]),
  WorkspaceRef = deep_get(Task, [links, workspace_ref]),
  TaskWorkspace = filename:join([CaseDir, ensure_list(WorkspaceRef)]),
  ?assertEqual(TemplateId, deep_get(Task, [spec, template_ref])),
  ?assertEqual(TemplateId, deep_get(Version, [links, derived_from_template_ref])),
  ?assert(filelib:is_file(RegistryPath)),
  ?assert(filelib:is_file(CaseHistoryPath)),
  ?assert(filelib:is_file(TaskHistoryPath)),
  ?assert(length(file_lines(CaseHistoryPath)) > 0),
  ?assert(length(file_lines(TaskHistoryPath)) > 0),
  ?assert(filelib:is_file(filename:join([TaskWorkspace, "TASK.md"]))),
  ok.

revise_task_rejects_stale_revision_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{case_id => CaseId, candidate_id => id_of(Candidate), approved_by_op_id => <<"lemon">>, approval_summary => <<"Approve">>}
    ),
  Task = maps:get(task, Approved),
  TaskId = id_of(Task),
  GovernanceSid = deep_get(Task, [links, governance_session_id]),
  CurrentRevision = deep_get(Task, [header, revision]),

  ?assertMatch(
    {error, {revision_conflict, CurrentRevision}},
    openagentic_case_store:revise_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        governance_session_id => GovernanceSid,
        revised_by_op_id => <<"lemon">>,
        expected_revision => CurrentRevision - 1,
        objective => <<"new objective">>
      }
    )
  ),
  ok.

global_inbox_read_archive_filter_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, _Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),

  {ok, Inbox0} = openagentic_case_store:list_inbox(Root, #{}),
  [Mail0 | _] = Inbox0,
  MailId = id_of(Mail0),
  ?assertEqual(<<"unread">>, deep_get(Mail0, [state, status])),

  {ok, ReadMail} =
    openagentic_case_store:update_mail_state(
      Root,
      #{case_id => CaseId, mail_id => MailId, status => <<"read">>, acted_by_op_id => <<"lemon">>}
    ),
  ?assertEqual(<<"read">>, deep_get(ReadMail, [state, status])),

  {ok, InboxUnread} = openagentic_case_store:list_inbox(Root, #{status => <<"unread">>}),
  ?assertEqual([], InboxUnread),
  {ok, InboxRead} = openagentic_case_store:list_inbox(Root, #{status => <<"read">>}),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= MailId end, InboxRead)),

  {ok, ArchivedMail} =
    openagentic_case_store:update_mail_state(
      Root,
      #{case_id => CaseId, mail_id => MailId, status => <<"archived">>, acted_by_op_id => <<"lemon">>}
    ),
  ?assertEqual(<<"archived">>, deep_get(ArchivedMail, [state, status])),
  {ok, InboxArchived} = openagentic_case_store:list_inbox(Root, #{status => <<"archived">>}),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= MailId end, InboxArchived)),
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

file_lines(Path) ->
  {ok, Bin} = file:read_file(Path),
  [Line || Line <- binary:split(Bin, <<"\n">>, [global]), Line =/= <<>>].
