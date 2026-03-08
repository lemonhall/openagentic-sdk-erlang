-module(openagentic_case_store_candidate_approve_build).
-export([build_context/3, build_task/5, build_version/4]).

build_context(CaseDir, Candidate0, Input) ->
  Now = openagentic_case_store_common_meta:now_ts(),
  TaskId = openagentic_case_store_common_meta:new_id(<<"task">>),
  VersionId = openagentic_case_store_common_meta:new_id(<<"version">>),
  CaseSnapshot = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:case_file(CaseDir)),
  Title = openagentic_case_store_common_lookup:get_bin(Input, [title], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, title], <<"Untitled Task">>)),
  MissionStatement = openagentic_case_store_common_lookup:get_bin(Input, [mission_statement, missionStatement], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, mission_statement], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, objective], Title))),
  CredentialRequirements = openagentic_case_store_common_lookup:choose_map(Input, [credential_requirements, credentialRequirements], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, credential_requirements], #{})),
  #{
    now => Now,
    task_id => TaskId,
    version_id => VersionId,
    governance_session_id => openagentic_case_store_common_lookup:get_in_map(Candidate0, [links, review_session_id], <<>>),
    workspace_ref => <<"workspaces/", TaskId/binary>>,
    title => Title,
    display_code => openagentic_case_store_common_lookup:get_bin(Input, [display_code, displayCode], openagentic_case_store_common_meta:display_code(<<"TASK">>)),
    mission_statement => MissionStatement,
    template_ref => openagentic_case_store_common_lookup:get_bin(Input, [template_ref, templateRef], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, template_ref], undefined)),
    default_timezone => openagentic_case_store_common_lookup:get_bin(Input, [default_timezone, defaultTimezone], openagentic_case_store_common_meta:default_timezone(CaseSnapshot)),
    schedule_policy => openagentic_case_store_common_lookup:choose_map(Input, [schedule_policy, schedulePolicy], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, schedule_policy], openagentic_case_store_case_support:default_schedule_policy(openagentic_case_store_common_meta:default_timezone(CaseSnapshot)))),
    report_contract => openagentic_case_store_common_lookup:choose_map(Input, [report_contract, reportContract], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, report_contract], openagentic_case_store_case_support:default_report_contract())),
    alert_rules => openagentic_case_store_common_lookup:choose_map(Input, [alert_rules, alertRules], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, alert_rules], #{})),
    source_strategy => openagentic_case_store_common_lookup:choose_map(Input, [source_strategy, sourceStrategy], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, source_strategy], #{})),
    tool_profile => openagentic_case_store_common_lookup:choose_map(Input, [tool_profile, toolProfile], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, tool_profile], #{})),
    credential_requirements => CredentialRequirements,
    autonomy_policy => openagentic_case_store_common_lookup:choose_map(Input, [autonomy_policy, autonomyPolicy], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, autonomy_policy], #{})),
    promotion_policy => openagentic_case_store_common_lookup:choose_map(Input, [promotion_policy, promotionPolicy], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, promotion_policy], #{})),
    task_status => openagentic_case_store_common_meta:initial_task_status(CredentialRequirements),
    objective => openagentic_case_store_common_lookup:get_bin(Input, [objective], openagentic_case_store_common_lookup:get_in_map(Candidate0, [spec, objective], MissionStatement))
  }.

build_task(CaseId, CandidateId, Candidate0, Input, Context) ->
  TaskStatus = maps:get(task_status, Context),
  Now = maps:get(now, Context),
  #{
    header => openagentic_case_store_common_meta:header(maps:get(task_id, Context), <<"monitoring_task">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, source_round_id => openagentic_case_store_common_lookup:get_in_map(Candidate0, [links, source_round_id], undefined), source_candidate_id => CandidateId, governance_session_id => maps:get(governance_session_id, Context), active_version_id => maps:get(version_id, Context), workspace_ref => maps:get(workspace_ref, Context), active_pack_ids => []}),
    spec => openagentic_case_store_common_meta:compact_map(#{title => maps:get(title, Context), display_code => maps:get(display_code, Context), mission_statement => maps:get(mission_statement, Context), default_timezone => maps:get(default_timezone, Context), schedule_policy_ref => undefined, template_ref => maps:get(template_ref, Context), credential_binding_refs => []}),
    state => #{status => TaskStatus, health => openagentic_case_store_common_meta:task_health_for_status(TaskStatus), activated_at => case TaskStatus of <<"active">> -> Now; _ -> undefined end, latest_run_id => undefined, latest_successful_run_id => undefined, last_report_at => undefined},
    audit => openagentic_case_store_common_meta:compact_map(#{approved_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [approved_by_op_id, approvedByOpId], undefined), approval_summary => openagentic_case_store_common_lookup:get_bin(Input, [approval_summary, approvalSummary], undefined)}),
    ext => #{}
  }.

build_version(CaseId, _Candidate0, Input, Context) ->
  Now = maps:get(now, Context),
  #{
    header => openagentic_case_store_common_meta:header(maps:get(version_id, Context), <<"task_version">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, task_id => maps:get(task_id, Context), previous_version_id => undefined, derived_from_template_ref => maps:get(template_ref, Context), approved_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [approved_by_op_id, approvedByOpId], undefined)}),
    spec => openagentic_case_store_common_meta:compact_map(#{objective => maps:get(objective, Context), schedule_policy => maps:get(schedule_policy, Context), report_contract => maps:get(report_contract, Context), alert_rules => maps:get(alert_rules, Context), source_strategy => maps:get(source_strategy, Context), tool_profile => maps:get(tool_profile, Context), credential_requirements => maps:get(credential_requirements, Context), autonomy_policy => maps:get(autonomy_policy, Context), promotion_policy => maps:get(promotion_policy, Context)}),
    state => #{status => <<"active">>, activated_at => Now, superseded_at => undefined},
    audit => openagentic_case_store_common_meta:compact_map(#{change_summary => openagentic_case_store_common_lookup:get_bin(Input, [change_summary, changeSummary], <<"create initial version">>), approval_summary => openagentic_case_store_common_lookup:get_bin(Input, [approval_summary, approvalSummary], undefined)}),
    ext => #{}
  }.
