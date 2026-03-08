-module(openagentic_case_store_api_templates).
-export([create_template/2, instantiate_template_candidate/2]).

create_template(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      Now = openagentic_case_store_common_meta:now_ts(),
      TemplateId = openagentic_case_store_common_meta:new_id(<<"template">>),
      WorkspaceRef = <<"workspaces/templates/", TemplateId/binary>>,
      TemplateWorkspaceDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(WorkspaceRef)]),
      ok = filelib:ensure_dir(filename:join([TemplateWorkspaceDir, "x"])),
      ok = openagentic_case_store_case_support:seed_template_workspace(TemplateWorkspaceDir, Input, CaseObj),
      DefaultTimezone = openagentic_case_store_common_lookup:get_bin(Input, [default_timezone, defaultTimezone], openagentic_case_store_common_meta:default_timezone(CaseObj)),
      TemplateObj =
        #{
          header => openagentic_case_store_common_meta:header(TemplateId, <<"task_template">>, Now),
          links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, workspace_ref => WorkspaceRef}),
          spec =>
            openagentic_case_store_common_meta:compact_map(
              #{
                title => openagentic_case_store_common_lookup:get_bin(Input, [title], <<"Untitled Template">>),
                summary => openagentic_case_store_common_lookup:get_bin(Input, [summary], undefined),
                objective => openagentic_case_store_common_lookup:get_bin(Input, [objective], undefined),
                default_timezone => DefaultTimezone,
                schedule_policy =>
                  openagentic_case_store_common_lookup:choose_map(
                    Input,
                    [schedule_policy, schedulePolicy],
                    openagentic_case_store_case_support:default_schedule_policy(DefaultTimezone)
                  ),
                report_contract => openagentic_case_store_common_lookup:choose_map(Input, [report_contract, reportContract], openagentic_case_store_case_support:default_report_contract()),
                alert_rules => openagentic_case_store_common_lookup:choose_map(Input, [alert_rules, alertRules], #{}),
                source_strategy => openagentic_case_store_common_lookup:choose_map(Input, [source_strategy, sourceStrategy], #{}),
                tool_profile => openagentic_case_store_common_lookup:choose_map(Input, [tool_profile, toolProfile], #{}),
                credential_requirements => openagentic_case_store_common_lookup:choose_map(Input, [credential_requirements, credentialRequirements], #{}),
                autonomy_policy => openagentic_case_store_common_lookup:choose_map(Input, [autonomy_policy, autonomyPolicy], #{}),
                promotion_policy => openagentic_case_store_common_lookup:choose_map(Input, [promotion_policy, promotionPolicy], #{}),
                template_body_ref => <<WorkspaceRef/binary, "/TEMPLATE.md">>
              }
            ),
          state => #{status => <<"active">>},
          audit => openagentic_case_store_common_meta:compact_map(#{created_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [created_by_op_id, createdByOpId], undefined)}),
          ext => #{}
        },
      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:template_file(CaseDir, TemplateId), TemplateObj),
      ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
      {ok, #{template => TemplateObj, templates => openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_template_objects(filename:join([CaseDir, "meta", "templates"]))), overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}
  end.

instantiate_template_candidate(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TemplateId = openagentic_case_store_common_lookup:required_bin(Input, [template_id, templateId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      TemplatePath = openagentic_case_store_repo_paths:template_file(CaseDir, TemplateId),
      case filelib:is_file(TemplatePath) of
        false -> {error, not_found};
        true ->
          Now = openagentic_case_store_common_meta:now_ts(),
          TemplateObj = openagentic_case_store_repo_persist:read_json(TemplatePath),
          RoundId = openagentic_case_store_candidates_infer:resolve_round_id(CaseDir, Input, CaseObj),
          RoundObj = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:round_file(CaseDir, RoundId)),
          WorkflowSessionId = openagentic_case_store_common_lookup:get_in_map(RoundObj, [links, workflow_session_id], undefined),
          CandidateId = openagentic_case_store_common_meta:new_id(<<"candidate">>),
          {ok, ReviewSessionId0} =
            openagentic_session_store:create_session(
              RootDir,
              #{
                kind => <<"candidate_review">>,
                case_id => CaseId,
                round_id => RoundId,
                candidate_id => CandidateId,
                template_id => TemplateId
              }
            ),
          ReviewSessionId = openagentic_case_store_common_core:to_bin(ReviewSessionId0),
          CandidateSpec = openagentic_case_store_candidates_infer:template_candidate_spec(TemplateObj, Input, CaseObj),
          CandidateObj = openagentic_case_store_candidates_build:build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, CandidateSpec#{template_ref => TemplateId}, Now),
          MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
          MailObj = openagentic_case_store_candidates_build:build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now),
          ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:candidate_file(CaseDir, CandidateId), CandidateObj),
          ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:mail_file(CaseDir, MailId), MailObj),
          ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
          {ok, #{candidate => CandidateObj, mail => MailObj, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}
      end
  end.
