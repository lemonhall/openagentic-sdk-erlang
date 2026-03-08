-module(openagentic_case_store).

-export([
  create_case_from_round/2,
  extract_candidates/2,
  approve_candidate/2,
  discard_candidate/2,
  get_case_overview/2,
  list_templates/2,
  create_template/2,
  instantiate_template_candidate/2,
  list_inbox/2,
  update_mail_state/2,
  get_task_detail/3,
  revise_task/2,
  upsert_credential_binding/2,
  invalidate_credential_binding/2,
  activate_task/2,
  run_task/2,
  retry_run/2
]).

create_case_from_round(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  WorkflowSessionId = required_bin(Input, [workflow_session_id, workflowSessionId]),
  try
    _ = openagentic_session_store:session_dir(RootDir, ensure_list(WorkflowSessionId)),
    ok = ensure_workflow_session_completed(RootDir, WorkflowSessionId),
    Now = now_ts(),
    CaseId = new_id(<<"case">>),
    RoundId = new_id(<<"round">>),
    CaseDir = case_dir(RootDir, CaseId),
    ok = ensure_case_layout(CaseDir),
    CaseObj =
      #{
        header => header(CaseId, <<"case">>, Now),
        links =>
          compact_map(
            #{
              origin_round_id => RoundId,
              origin_workflow_session_id => WorkflowSessionId,
              current_round_id => RoundId,
              latest_briefing_id => undefined,
              active_pack_ids => []
            }
          ),
        spec =>
          compact_map(
            #{
              title => get_bin(Input, [title], <<"Untitled Case">>),
              display_code => get_bin(Input, [display_code, displayCode], display_code(<<"CASE">>)),
              topic => get_bin(Input, [topic], undefined),
              owner => get_bin(Input, [owner], undefined),
              default_timezone => get_bin(Input, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>),
              labels => get_list(Input, [labels], []),
              opening_brief => get_bin(Input, [opening_brief, openingBrief], <<>>)
            }
          ),
        state =>
          #{
            status => <<"active">>,
            phase => <<"post_deliberation_extraction">>,
            current_summary => get_bin(Input, [current_summary, currentSummary], <<>>),
            active_task_count => 0,
            active_pack_count => 0
          },
        audit =>
          compact_map(
            #{
              created_from => <<"workflow_session">>,
              created_from_session_id => WorkflowSessionId,
              created_by => get_bin(Input, [created_by, createdBy], undefined)
            }
          ),
        ext => #{}
      },
    RoundObj =
      #{
        header => header(RoundId, <<"deliberation_round">>, Now),
        links =>
          compact_map(
            #{
              case_id => CaseId,
              parent_round_id => get_bin(Input, [parent_round_id, parentRoundId], undefined),
              workflow_session_id => WorkflowSessionId,
              triggering_briefing_id => get_bin(Input, [triggering_briefing_id, triggeringBriefingId], undefined),
              resolution_id => get_bin(Input, [resolution_id, resolutionId], undefined)
            }
          ),
        spec =>
          compact_map(
            #{
              round_index => get_int(Input, [round_index, roundIndex], 1),
              kind => get_bin(Input, [kind], <<"initial_deliberation">>),
              trigger_reason => get_bin(Input, [trigger_reason, triggerReason], <<"workflow_session_promoted_to_case">>),
              starter_role => get_bin(Input, [starter_role, starterRole], <<"court">>),
              input_material_refs => get_list(Input, [input_material_refs, inputMaterialRefs], [])
            }
          ),
        state =>
          compact_map(
            #{
              status => get_bin(Input, [round_status, roundStatus], <<"completed">>),
              phase => get_bin(Input, [round_phase, roundPhase], <<"concluded">>),
              started_at => get_number(Input, [started_at, startedAt], undefined),
              ended_at => Now
            }
          ),
        audit => compact_map(#{created_from_session_id => WorkflowSessionId}),
        ext => #{}
      },
    ok = persist_case_object(CaseDir, case_file(CaseDir), CaseObj),
    ok = persist_case_object(CaseDir, round_file(CaseDir, RoundId), RoundObj),
    ok = rebuild_indexes(RootDir, CaseId),
    BaseRes = #{'case' => CaseObj, round => RoundObj},
    case get_bool(Input, [auto_extract, autoExtract], true) of
      true ->
        case extract_candidates(RootDir, #{case_id => CaseId, round_id => RoundId}) of
          {ok, Extracted} ->
            {ok,
             maps:merge(
               BaseRes,
               #{
                 candidates => maps:get(candidates, Extracted, []),
                 mail => maps:get(mail, Extracted, []),
                 overview => maps:get(overview, Extracted, undefined)
               }
             )};
          {error, ExtractReason} -> {error, ExtractReason}
        end;
      false ->
        {ok, BaseRes}
    end
  catch
    error:{missing_required_field, Field} -> {error, {missing_required_field, Field}};
    error:{invalid_session_id, _} -> {error, invalid_workflow_session_id};
    throw:{error, Reason} -> {error, Reason}
  end.

extract_candidates(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  {ok, CaseObj, CaseDir} = load_case(RootDir, CaseId),
  RoundId = resolve_round_id(CaseDir, Input, CaseObj),
  RoundObj = read_json(round_file(CaseDir, RoundId)),
  WorkflowSessionId = get_in_map(RoundObj, [links, workflow_session_id], <<>>),
  Items0 = get_list(Input, [items, candidates], []),
  CandidateSpecs =
    case normalize_candidate_specs(Items0) of
      [] -> infer_candidate_specs_from_session(RootDir, WorkflowSessionId, default_timezone(CaseObj));
      Specs -> Specs
    end,
  Now = now_ts(),
  {Candidates, Mail} = create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, CandidateSpecs, Now),
  ok = rebuild_indexes(RootDir, CaseId),
  {ok, #{case_id => CaseId, round_id => RoundId, candidates => Candidates, mail => Mail, overview => get_case_overview_map(RootDir, CaseId)}}.

approve_candidate(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  CandidateId = required_bin(Input, [candidate_id, candidateId]),
  {ok, _CaseObj, CaseDir} = load_case(RootDir, CaseId),
  CandidatePath = candidate_file(CaseDir, CandidateId),
  Candidate0 = read_json(CandidatePath),
  CandidateStatus = get_in_map(Candidate0, [state, status], <<>>),
  case CandidateStatus of
    <<"approved">> -> {error, already_approved};
    <<"discarded">> -> {error, candidate_discarded};
    _ ->
      Now = now_ts(),
      TaskId = new_id(<<"task">>),
      VersionId = new_id(<<"version">>),
      GovernanceSessionId = get_in_map(Candidate0, [links, review_session_id], <<>>),
      WorkspaceRef = <<"workspaces/", TaskId/binary>>,
      TaskWorkspaceDir = filename:join([CaseDir, ensure_list(WorkspaceRef)]),
      ok = filelib:ensure_dir(filename:join([TaskWorkspaceDir, "x"])),
      ok = seed_task_workspace(TaskWorkspaceDir, Candidate0, Input),
      Title = get_bin(Input, [title], get_in_map(Candidate0, [spec, title], <<"Untitled Task">>)),
      DisplayCode = get_bin(Input, [display_code, displayCode], display_code(<<"TASK">>)),
      MissionStatement =
        get_bin(
          Input,
          [mission_statement, missionStatement],
          get_in_map(Candidate0, [spec, mission_statement], get_in_map(Candidate0, [spec, objective], Title))
        ),
      TemplateRef = get_bin(Input, [template_ref, templateRef], get_in_map(Candidate0, [spec, template_ref], undefined)),
      CaseSnapshot = read_json(case_file(CaseDir)),
      SchedulePolicy =
        choose_map(
          Input,
          [schedule_policy, schedulePolicy],
          get_in_map(Candidate0, [spec, schedule_policy], default_schedule_policy(default_timezone(CaseSnapshot)))
        ),
      ReportContract =
        choose_map(
          Input,
          [report_contract, reportContract],
          get_in_map(Candidate0, [spec, report_contract], default_report_contract())
        ),
      AlertRules = choose_map(Input, [alert_rules, alertRules], get_in_map(Candidate0, [spec, alert_rules], #{})),
      SourceStrategy = choose_map(Input, [source_strategy, sourceStrategy], get_in_map(Candidate0, [spec, source_strategy], #{})),
      ToolProfile = choose_map(Input, [tool_profile, toolProfile], get_in_map(Candidate0, [spec, tool_profile], #{})),
      CredentialRequirements =
        choose_map(
          Input,
          [credential_requirements, credentialRequirements],
          get_in_map(Candidate0, [spec, credential_requirements], #{})
        ),
      AutonomyPolicy = choose_map(Input, [autonomy_policy, autonomyPolicy], get_in_map(Candidate0, [spec, autonomy_policy], #{})),
      PromotionPolicy = choose_map(Input, [promotion_policy, promotionPolicy], get_in_map(Candidate0, [spec, promotion_policy], #{})),
      TaskStatus = initial_task_status(CredentialRequirements),
      TaskObj =
        #{
          header => header(TaskId, <<"monitoring_task">>, Now),
          links =>
            compact_map(
              #{
                case_id => CaseId,
                source_round_id => get_in_map(Candidate0, [links, source_round_id], undefined),
                source_candidate_id => CandidateId,
                governance_session_id => GovernanceSessionId,
                active_version_id => VersionId,
                workspace_ref => WorkspaceRef,
                active_pack_ids => []
              }
            ),
          spec =>
            compact_map(
              #{
                title => Title,
                display_code => DisplayCode,
                mission_statement => MissionStatement,
                default_timezone => get_bin(Input, [default_timezone, defaultTimezone], default_timezone(CaseSnapshot)),
                schedule_policy_ref => undefined,
                template_ref => TemplateRef,
                credential_binding_refs => []
              }
            ),
          state =>
            #{
              status => TaskStatus,
              health => task_health_for_status(TaskStatus),
              activated_at =>
                case TaskStatus of
                  <<"active">> -> Now;
                  _ -> undefined
                end,
              latest_run_id => undefined,
              latest_successful_run_id => undefined,
              last_report_at => undefined
            },
          audit =>
            compact_map(
              #{
                approved_by_op_id => get_bin(Input, [approved_by_op_id, approvedByOpId], undefined),
                approval_summary => get_bin(Input, [approval_summary, approvalSummary], undefined)
              }
            ),
          ext => #{}
        },
      TaskVersionObj =
        #{
          header => header(VersionId, <<"task_version">>, Now),
          links =>
            compact_map(
              #{
                case_id => CaseId,
                task_id => TaskId,
                previous_version_id => undefined,
                derived_from_template_ref => TemplateRef,
                approved_by_op_id => get_bin(Input, [approved_by_op_id, approvedByOpId], undefined)
              }
            ),
          spec =>
            compact_map(
              #{
                objective => get_bin(Input, [objective], get_in_map(Candidate0, [spec, objective], MissionStatement)),
                schedule_policy => SchedulePolicy,
                report_contract => ReportContract,
                alert_rules => AlertRules,
                source_strategy => SourceStrategy,
                tool_profile => ToolProfile,
                credential_requirements => CredentialRequirements,
                autonomy_policy => AutonomyPolicy,
                promotion_policy => PromotionPolicy
              }
            ),
          state => #{status => <<"active">>, activated_at => Now, superseded_at => undefined},
          audit =>
            compact_map(
              #{
                change_summary => get_bin(Input, [change_summary, changeSummary], <<"create initial version">>),
                approval_summary => get_bin(Input, [approval_summary, approvalSummary], undefined)
              }
            ),
          ext => #{}
        },
      ok = persist_case_object(CaseDir, task_file(CaseDir, TaskId), TaskObj),
      ok = persist_case_object(CaseDir, task_version_file(CaseDir, TaskId, VersionId), TaskVersionObj),
      Candidate1 =
        update_object(
          Candidate0,
          Now,
          fun (Obj) ->
            Obj#{
              links => maps:put(approved_task_id, TaskId, maps:get(links, Obj, #{})),
              state => maps:put(status, <<"approved">>, maps:get(state, Obj, #{})),
              audit =>
                maps:merge(
                  maps:get(audit, Obj, #{}),
                  compact_map(
                    #{
                      approved_at => Now,
                      approved_by_op_id => get_bin(Input, [approved_by_op_id, approvedByOpId], undefined),
                      approval_summary => get_bin(Input, [approval_summary, approvalSummary], undefined)
                    }
                  )
                )
            }
          end
        ),
      ok = persist_case_object(CaseDir, CandidatePath, Candidate1),
      ok = mark_candidate_mail_acted(CaseDir, CandidateId, <<"approve">>, get_bin(Input, [approved_by_op_id, approvedByOpId], undefined), Now),
      ok = refresh_case_state(RootDir, CaseId),
      ok = rebuild_indexes(RootDir, CaseId),
      {ok, #{candidate => Candidate1, task => TaskObj, task_version => TaskVersionObj, overview => get_case_overview_map(RootDir, CaseId)}}
  end.

discard_candidate(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  CandidateId = required_bin(Input, [candidate_id, candidateId]),
  {ok, _CaseObj, CaseDir} = load_case(RootDir, CaseId),
  CandidatePath = candidate_file(CaseDir, CandidateId),
  Candidate0 = read_json(CandidatePath),
  Now = now_ts(),
  Candidate1 =
    update_object(
      Candidate0,
      Now,
      fun (Obj) ->
        Obj#{
          state => maps:put(status, <<"discarded">>, maps:get(state, Obj, #{})),
          audit =>
            maps:merge(
              maps:get(audit, Obj, #{}),
              compact_map(
                #{
                  discarded_at => Now,
                  discarded_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                  discard_reason => get_bin(Input, [reason], undefined)
                }
              )
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, CandidatePath, Candidate1),
  ok = mark_candidate_mail_acted(CaseDir, CandidateId, <<"discard">>, get_bin(Input, [acted_by_op_id, actedByOpId], undefined), Now),
  ok = refresh_case_state(RootDir, CaseId),
  ok = rebuild_indexes(RootDir, CaseId),
  {ok, Candidate1}.

get_case_overview(RootDir0, CaseId0) ->
  RootDir = ensure_list(RootDir0),
  CaseId = to_bin(CaseId0),
  case load_case(RootDir, CaseId) of
    {ok, _CaseObj, _CaseDir} -> {ok, get_case_overview_map(RootDir, CaseId)};
    {error, Reason} -> {error, Reason}
  end.

list_templates(RootDir0, CaseIdOrInput) ->
  RootDir = ensure_list(RootDir0),
  CaseId =
    case CaseIdOrInput of
      Map when is_map(Map) -> required_bin(Map, [case_id, caseId]);
      Value -> to_bin(Value)
    end,
  case load_case(RootDir, CaseId) of
    {ok, _CaseObj, CaseDir} ->
      {ok, sort_by_created_at(read_template_objects(filename:join([CaseDir, "meta", "templates"])))};
    {error, Reason} -> {error, Reason}
  end.

create_template(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      Now = now_ts(),
      TemplateId = new_id(<<"template">>),
      WorkspaceRef = <<"workspaces/templates/", TemplateId/binary>>,
      TemplateWorkspaceDir = filename:join([CaseDir, ensure_list(WorkspaceRef)]),
      ok = filelib:ensure_dir(filename:join([TemplateWorkspaceDir, "x"])),
      ok = seed_template_workspace(TemplateWorkspaceDir, Input, CaseObj),
      DefaultTimezone = get_bin(Input, [default_timezone, defaultTimezone], default_timezone(CaseObj)),
      TemplateObj =
        #{
          header => header(TemplateId, <<"task_template">>, Now),
          links => compact_map(#{case_id => CaseId, workspace_ref => WorkspaceRef}),
          spec =>
            compact_map(
              #{
                title => get_bin(Input, [title], <<"Untitled Template">>),
                summary => get_bin(Input, [summary], undefined),
                objective => get_bin(Input, [objective], undefined),
                default_timezone => DefaultTimezone,
                schedule_policy =>
                  choose_map(
                    Input,
                    [schedule_policy, schedulePolicy],
                    default_schedule_policy(DefaultTimezone)
                  ),
                report_contract => choose_map(Input, [report_contract, reportContract], default_report_contract()),
                alert_rules => choose_map(Input, [alert_rules, alertRules], #{}),
                source_strategy => choose_map(Input, [source_strategy, sourceStrategy], #{}),
                tool_profile => choose_map(Input, [tool_profile, toolProfile], #{}),
                credential_requirements => choose_map(Input, [credential_requirements, credentialRequirements], #{}),
                autonomy_policy => choose_map(Input, [autonomy_policy, autonomyPolicy], #{}),
                promotion_policy => choose_map(Input, [promotion_policy, promotionPolicy], #{}),
                template_body_ref => <<WorkspaceRef/binary, "/TEMPLATE.md">>
              }
            ),
          state => #{status => <<"active">>},
          audit => compact_map(#{created_by_op_id => get_bin(Input, [created_by_op_id, createdByOpId], undefined)}),
          ext => #{}
        },
      ok = persist_case_object(CaseDir, template_file(CaseDir, TemplateId), TemplateObj),
      ok = rebuild_indexes(RootDir, CaseId),
      {ok, #{template => TemplateObj, templates => sort_by_created_at(read_template_objects(filename:join([CaseDir, "meta", "templates"]))), overview => get_case_overview_map(RootDir, CaseId)}}
  end.

instantiate_template_candidate(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TemplateId = required_bin(Input, [template_id, templateId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      TemplatePath = template_file(CaseDir, TemplateId),
      case filelib:is_file(TemplatePath) of
        false -> {error, not_found};
        true ->
          Now = now_ts(),
          TemplateObj = read_json(TemplatePath),
          RoundId = resolve_round_id(CaseDir, Input, CaseObj),
          RoundObj = read_json(round_file(CaseDir, RoundId)),
          WorkflowSessionId = get_in_map(RoundObj, [links, workflow_session_id], undefined),
          CandidateId = new_id(<<"candidate">>),
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
          ReviewSessionId = to_bin(ReviewSessionId0),
          CandidateSpec = template_candidate_spec(TemplateObj, Input, CaseObj),
          CandidateObj = build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, CandidateSpec#{template_ref => TemplateId}, Now),
          MailId = new_id(<<"mail">>),
          MailObj = build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now),
          ok = persist_case_object(CaseDir, candidate_file(CaseDir, CandidateId), CandidateObj),
          ok = persist_case_object(CaseDir, mail_file(CaseDir, MailId), MailObj),
          ok = rebuild_indexes(RootDir, CaseId),
          {ok, #{candidate => CandidateObj, mail => MailObj, overview => get_case_overview_map(RootDir, CaseId)}}
      end
  end.

list_inbox(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  StatusFilter = get_bin(Input, [status], undefined),
  CaseFilter = get_bin(Input, [case_id, caseId], undefined),
  CasesRoot = filename:join([RootDir, "cases"]),
  Mail0 =
    lists:foldl(
      fun (CaseName, Acc) ->
        CaseId = to_bin(CaseName),
        case CaseFilter =:= undefined orelse CaseFilter =:= CaseId of
          false -> Acc;
          true ->
            CaseDir = case_dir(RootDir, CaseId),
            case filelib:is_file(case_file(CaseDir)) of
              false -> Acc;
              true ->
                CaseObj = read_json(case_file(CaseDir)),
                MailItems =
                  [decorate_global_mail(Item, CaseObj) || Item <- read_objects_in_dir(filename:join([CaseDir, "meta", "mail"]))],
                Acc ++ MailItems
            end
        end
      end,
      [],
      safe_list_dir(CasesRoot)
    ),
  Mail1 =
    case StatusFilter of
      undefined -> Mail0;
      <<"all">> -> Mail0;
      _ -> [Item || Item <- Mail0, get_in_map(Item, [state, status], <<>>) =:= StatusFilter]
    end,
  {ok, lists:reverse(sort_by_created_at(Mail1))}.

update_mail_state(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  MailId = required_bin(Input, [mail_id, mailId]),
  Status = required_bin(Input, [status]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      MailPath = mail_file(CaseDir, MailId),
      case filelib:is_file(MailPath) of
        false -> {error, not_found};
        true ->
          Mail0 = read_json(MailPath),
          case maybe_check_expected_revision(Input, Mail0) of
            ok ->
              Now = now_ts(),
              MailDir = filename:join([CaseDir, "meta", "mail"]),
              Mail1 = update_mail_status(Mail0, Input, Status, Now),
              lists:foreach(
                fun (Path) ->
                  MailObj0 = read_json(Path),
                  MailObj1 = update_mail_status(MailObj0, Input, Status, Now),
                  ok = persist_case_object(CaseDir, Path, MailObj1)
                end,
                json_files(MailDir)
              ),
              ok = rebuild_indexes(RootDir, CaseId),
              {ok, Mail1};
            {error, Reason} -> {error, Reason}
          end
      end
  end.

get_task_detail(RootDir0, CaseId0, TaskId0) ->
  RootDir = ensure_list(RootDir0),
  CaseId = to_bin(CaseId0),
  TaskId = to_bin(TaskId0),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Task = read_json(TaskPath),
          Versions = read_task_versions(CaseDir, TaskId),
          CredentialBindings = read_task_credential_bindings(CaseDir, TaskId),
          Runs = lists:reverse(read_task_runs(CaseDir, TaskId)),
          Attempts = lists:reverse(read_task_run_attempts(CaseDir, TaskId)),
          Reports = lists:reverse(read_task_fact_reports(CaseDir, TaskId)),
          Briefs = lists:reverse(read_task_exception_briefs(CaseDir, TaskId)),
          Authorization = build_task_authorization(Task, Versions, CredentialBindings),
          FailureStats = build_task_failure_stats(Runs, Attempts),
          VersionSummary = build_historical_version_summary(Versions),
          ExecutionSummary = build_historical_execution_summary(Runs, Attempts, Reports),
          LatestExceptionSummary = build_latest_exception_summary(Attempts, Briefs),
          LatestReportSummary = build_latest_report_summary(Reports),
          RecentRectificationSummary = build_recent_rectification_summary(Versions),
          {ok,
           #{
              task => Task,
              versions => Versions,
              credential_bindings => CredentialBindings,
              authorization => Authorization,
              latest_version_diff => build_latest_version_diff(Versions, Authorization),
              runs => Runs,
              run_attempts => Attempts,
              fact_reports => Reports,
              exception_briefs => Briefs,
              failure_stats => FailureStats,
              historical_version_summary => VersionSummary,
              historical_execution_summary => ExecutionSummary,
              latest_exception_summary => LatestExceptionSummary,
              latest_report_summary => LatestReportSummary,
              recent_rectification_summary => RecentRectificationSummary,
              artifacts => build_task_artifacts(Reports)
            }}
      end
  end.

revise_task(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  GovernanceSessionId = required_bin(Input, [governance_session_id, governanceSessionId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Task0 = read_json(TaskPath),
          case maybe_check_expected_revision(Input, Task0) of
            ok ->
              case get_in_map(Task0, [links, governance_session_id], <<>>) of
                <<>> -> {error, governance_session_missing};
                GovernanceSessionId ->
                  revise_task_with_session(RootDir, CaseId, CaseDir, Task0, Input, GovernanceSessionId);
                _ -> {error, governance_session_mismatch}
              end;
            {error, Reason} -> {error, Reason}
          end
      end
  end.

upsert_credential_binding(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Now = now_ts(),
          Task0 = read_json(TaskPath),
          ExistingBindings = read_task_credential_bindings(CaseDir, TaskId),
          RotateBindingId = get_bin(Input, [rotate_binding_id, rotateBindingId], undefined),
          ExistingBindingId = get_bin(Input, [credential_binding_id, credentialBindingId], undefined),
          case resolve_binding_context(Input, ExistingBindings, RotateBindingId, ExistingBindingId) of
            {error, Reason} -> {error, Reason};
            {ok, SlotName, BindingDefaults, ExistingBinding0} ->
              case ExistingBinding0 =:= undefined orelse maybe_check_expected_revision(Input, ExistingBinding0) =:= ok of
                false -> maybe_check_expected_revision(Input, ExistingBinding0);
                true ->
                  case RotateBindingId of
                    undefined ->
                      BindingId =
                        case ExistingBinding0 of
                          undefined -> resolve_credential_binding_id(Input, ExistingBindings);
                          _ -> id_of(ExistingBinding0)
                        end,
                      BindingPath = credential_binding_file(CaseDir, TaskId, BindingId),
                      BindingInput = maps:merge(BindingDefaults, Input),
                      Binding1 =
                        case ExistingBinding0 of
                          undefined -> build_credential_binding(CaseId, TaskId, BindingId, BindingInput, SlotName, Now);
                          _ -> update_credential_binding(ExistingBinding0, BindingInput, SlotName, Now)
                        end,
                      ok = persist_case_object(CaseDir, BindingPath, Binding1),
                      {Task1, Authorization} = sync_task_authorization(CaseDir, Task0, Now),
                      ok = refresh_case_state(RootDir, CaseId),
                      ok = rebuild_indexes(RootDir, CaseId),
                      {ok,
                       #{
                         credential_binding => Binding1,
                         credential_bindings => read_task_credential_bindings(CaseDir, TaskId),
                         task => Task1,
                         authorization => Authorization,
                         overview => get_case_overview_map(RootDir, CaseId)
                       }};
                    _ ->
                      RotatedFrom = ExistingBinding0,
                      BindingId = new_id(<<"binding">>),
                      BindingInput = maps:merge(BindingDefaults, Input),
                      RotatedFromPath = credential_binding_file(CaseDir, TaskId, id_of(RotatedFrom)),
                      BindingPath = credential_binding_file(CaseDir, TaskId, BindingId),
                      RotatedOld =
                        update_object(
                          RotatedFrom,
                          Now,
                          fun (Obj) ->
                            Obj#{
                              links => maps:merge(maps:get(links, Obj, #{}), #{rotated_to_binding_id => BindingId}),
                              state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"rotated">>, rotated_at => Now}),
                              audit =>
                                maps:merge(
                                  maps:get(audit, Obj, #{}),
                                  compact_map(
                                    #{
                                      updated_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                                      note => get_bin(Input, [note], undefined)
                                    }
                                  )
                                )
                            }
                          end
                        ),
                      RotatedNew0 = build_credential_binding(CaseId, TaskId, BindingId, BindingInput, SlotName, Now),
                      RotatedNew =
                        update_object(
                          RotatedNew0,
                          Now,
                          fun (Obj) ->
                            Obj#{
                              links => maps:merge(maps:get(links, Obj, #{}), #{rotated_from_binding_id => id_of(RotatedFrom)})
                            }
                          end
                        ),
                      ok = persist_case_object(CaseDir, RotatedFromPath, RotatedOld),
                      ok = persist_case_object(CaseDir, BindingPath, RotatedNew),
                      {Task1, Authorization} = sync_task_authorization(CaseDir, Task0, Now),
                      ok = refresh_case_state(RootDir, CaseId),
                      ok = rebuild_indexes(RootDir, CaseId),
                      {ok,
                       #{
                         credential_binding => RotatedNew,
                         credential_bindings => read_task_credential_bindings(CaseDir, TaskId),
                         task => Task1,
                         authorization => Authorization,
                         overview => get_case_overview_map(RootDir, CaseId)
                       }}
                  end
              end
          end
      end
  end.

invalidate_credential_binding(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  BindingId = required_bin(Input, [credential_binding_id, credentialBindingId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      BindingPath = credential_binding_file(CaseDir, TaskId, BindingId),
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(BindingPath) andalso filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Binding0 = read_json(BindingPath),
          case maybe_check_expected_revision(Input, Binding0) of
            ok ->
              Now = now_ts(),
              Binding1 =
                update_object(
                  Binding0,
                  Now,
                  fun (Obj) ->
                    Obj#{
                      state =>
                        maps:merge(
                          maps:get(state, Obj, #{}),
                          compact_map(
                            #{
                              status => get_bin(Input, [status], <<"invalidated">>),
                              invalidated_at => Now
                            }
                          )
                        ),
                      audit =>
                        maps:merge(
                          maps:get(audit, Obj, #{}),
                          compact_map(
                            #{
                              updated_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                              invalidation_reason => get_bin(Input, [reason], undefined),
                              note => get_bin(Input, [note], undefined)
                            }
                          )
                        )
                    }
                  end
                ),
              ok = persist_case_object(CaseDir, BindingPath, Binding1),
              Task0 = read_json(TaskPath),
              {Task1, Authorization} = sync_task_authorization(CaseDir, Task0, Now),
              ok = refresh_case_state(RootDir, CaseId),
              ok = rebuild_indexes(RootDir, CaseId),
              {ok,
               #{
                 credential_binding => Binding1,
                 credential_bindings => read_task_credential_bindings(CaseDir, TaskId),
                 task => Task1,
                 authorization => Authorization,
                 overview => get_case_overview_map(RootDir, CaseId)
               }};
            {error, Reason} -> {error, Reason}
          end
      end
  end.

activate_task(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  case load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Now = now_ts(),
          Task0 = read_json(TaskPath),
          Versions = read_task_versions(CaseDir, TaskId),
          CredentialBindings = read_task_credential_bindings(CaseDir, TaskId),
          Authorization = build_task_authorization(Task0, Versions, CredentialBindings),
          case activation_error(Authorization) of
            undefined ->
              Task1 =
                update_object(
                  Task0,
                  Now,
                  fun (Obj) ->
                    Obj#{
                      state =>
                        maps:merge(
                          maps:get(state, Obj, #{}),
                          #{status => <<"active">>, health => task_health_for_status(<<"active">>), activated_at => Now}
                        ),
                      audit =>
                        maps:merge(
                          maps:get(audit, Obj, #{}),
                          compact_map(
                            #{
                              activated_at => Now,
                              activated_by_op_id => get_bin(Input, [activated_by_op_id, activatedByOpId], undefined)
                            }
                          )
                        )
                    }
                  end
                ),
              ok = persist_case_object(CaseDir, TaskPath, Task1),
              ok = refresh_case_state(RootDir, CaseId),
              ok = rebuild_indexes(RootDir, CaseId),
              {ok,
               #{
                 task => Task1,
                 authorization => Authorization#{status => <<"active">>},
                 overview => get_case_overview_map(RootDir, CaseId)
               }};
            Error -> {error, Error}
          end
      end
  end.

run_task(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  case load_monitoring_task_context(RootDir, CaseId, TaskId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseDir, Task0, Version, Versions, CredentialBindings} ->
      case first_defined([task_run_in_progress_error(CaseDir, TaskId), run_task_error(Task0, Versions, CredentialBindings)]) of
        undefined ->
          Now = now_ts(),
          RunId = new_id(<<"run">>),
          Run0 = build_monitoring_run(CaseId, TaskId, id_of(Version), RunId, Version, Input, Now),
          ok = persist_case_object(CaseDir, run_file(CaseDir, TaskId, RunId), Run0),
          execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, undefined, Input);
        Error ->
          {error, Error}
      end
  end.

retry_run(RootDir0, Input0) ->
  RootDir = ensure_list(RootDir0),
  Input = ensure_map(Input0),
  CaseId = required_bin(Input, [case_id, caseId]),
  TaskId = required_bin(Input, [task_id, taskId]),
  RunId = required_bin(Input, [run_id, runId]),
  case load_monitoring_task_context(RootDir, CaseId, TaskId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseDir, Task0, _CurrentVersion, Versions, CredentialBindings} ->
      RunPath = run_file(CaseDir, TaskId, RunId),
      case filelib:is_file(RunPath) of
        false -> {error, not_found};
        true ->
          Run0 = read_json(RunPath),
          case retry_run_error(Task0, Run0, Versions, CredentialBindings) of
            undefined ->
              VersionId = get_in_map(Run0, [links, task_version_id], undefined),
              Version = load_task_version(CaseDir, TaskId, VersionId),
              PreviousAttemptId = get_in_map(Run0, [links, latest_attempt_id], undefined),
              execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, PreviousAttemptId, Input);
            Error ->
              {error, Error}
          end
      end
  end.

load_monitoring_task_context(RootDir, CaseId, TaskId) ->
  case load_case(RootDir, CaseId) of
    {error, Reason} ->
      {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false ->
          {error, not_found};
        true ->
          Task0 = read_json(TaskPath),
          Versions = read_task_versions(CaseDir, TaskId),
          CredentialBindings = read_task_credential_bindings(CaseDir, TaskId),
          case resolve_task_version(Task0, Versions) of
            undefined -> {error, no_task_version};
            Version -> {ok, CaseDir, Task0, Version, Versions, CredentialBindings}
          end
      end
  end.

resolve_task_version(Task0, Versions0) ->
  Versions = [ensure_map(V) || V <- Versions0],
  ActiveVersionId = get_in_map(Task0, [links, active_version_id], undefined),
  case [V || V <- Versions, id_of(V) =:= ActiveVersionId] of
    [Version | _] -> Version;
    [] ->
      case lists:reverse(Versions) of
        [Version | _] -> Version;
        [] -> undefined
      end
  end.

load_task_version(CaseDir, TaskId, undefined) ->
  resolve_task_version(#{links => #{}}, read_task_versions(CaseDir, TaskId));
load_task_version(CaseDir, TaskId, VersionId) ->
  Path = task_version_file(CaseDir, TaskId, VersionId),
  case filelib:is_file(Path) of
    true -> read_json(Path);
    false -> resolve_task_version(#{links => #{}}, read_task_versions(CaseDir, TaskId))
  end.

run_task_error(Task, Versions, CredentialBindings) ->
  Authorization = build_task_authorization(Task, Versions, CredentialBindings),
  case activation_error(Authorization) of
    undefined ->
      case get_in_map(Task, [state, status], <<"active">>) of
        <<"active">> -> undefined;
        <<"ready_to_activate">> -> ready_to_activate;
        <<"rectification_required">> -> rectification_required;
        <<"paused">> -> paused;
        Other when Other =:= <<"awaiting_credentials">>; Other =:= <<"credential_expired">>; Other =:= <<"reauthorization_required">> -> Other;
        _ -> undefined
      end;
    Error -> Error
  end.

retry_run_error(Task, Run, Versions, CredentialBindings) ->
  case run_task_error(Task, Versions, CredentialBindings) of
    undefined ->
      case {get_in_map(Run, [state, status], <<>>), get_in_map(Run, [links, successful_attempt_id], undefined)} of
        {<<"running">>, _} -> run_in_progress;
        {_, SuccessfulAttemptId} when SuccessfulAttemptId =/= undefined -> run_already_completed;
        _ -> undefined
      end;
    Error -> Error
  end.

execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, PreviousAttemptId, Input0) ->
  Input = ensure_map(Input0),
  Now = now_ts(),
  TaskId = id_of(Task0),
  RunId = id_of(Run0),
  AttemptId = new_id(<<"attempt">>),
  AttemptIndex = get_number(get_in_map(Run0, [state], #{}), [attempt_count], 0) + 1,
  ScratchRef = attempt_scratch_ref(TaskId, RunId, AttemptId),
  ScratchDir = filename:join([CaseDir, ensure_list(ScratchRef)]),
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  ExecutionSessionId = create_attempt_session(RootDir, CaseId, TaskId, RunId, AttemptId),
  CredentialBindings = read_task_credential_bindings(CaseDir, TaskId),
  CredentialSnapshot = build_credential_resolution_snapshot(CredentialBindings),
  AllowedTools = resolve_allowed_tools(Version),
  RunContext = build_monitoring_run_context(CaseDir, Task0, Version),
  ExecutionProfile = build_execution_profile_snapshot(Input, Task0, Version, AllowedTools, ScratchRef),
  Attempt0 =
    build_run_attempt(
      CaseId,
      TaskId,
      RunId,
      AttemptId,
      PreviousAttemptId,
      ExecutionSessionId,
      ScratchRef,
      AttemptIndex,
      Input,
      ExecutionProfile,
      CredentialSnapshot,
      Now
    ),
  ok = persist_case_object(CaseDir, run_attempt_file(CaseDir, TaskId, AttemptId), Attempt0),
  Run1 =
    update_object(
      Run0,
      Now,
      fun (Obj) ->
        Obj#{
          links => maps:merge(maps:get(links, Obj, #{}), #{latest_attempt_id => AttemptId}),
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"running">>, attempt_count => AttemptIndex, last_attempt_status => <<"running">>, started_at => Now}
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, run_file(CaseDir, TaskId, RunId), Run1),
  Task1 =
    update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{latest_run_id => RunId})}
      end
    ),
  ok = persist_case_object(CaseDir, task_file(CaseDir, TaskId), Task1),
  append_attempt_start_event(RootDir, ExecutionSessionId, CaseId, TaskId, RunId, AttemptId),
  Prompt = build_monitoring_prompt(Task1, Version, Attempt0, RunContext),
  RuntimeOpts = build_monitoring_runtime_opts(RootDir, CaseDir, Task1, ScratchDir, ExecutionSessionId, AllowedTools, Input),
  case openagentic_runtime:query(Prompt, RuntimeOpts) of
    {ok, RuntimeRes0} ->
      RuntimeRes = ensure_map(RuntimeRes0),
      FinalText = get_bin(RuntimeRes, [final_text, finalText], <<>>),
      case parse_monitoring_delivery(FinalText, TaskId, RunId, Now) of
        {ok, Delivery} ->
          case validate_report_contract(Version, Delivery) of
            ok ->
              finalize_run_success(RootDir, CaseId, CaseDir, Task1, Version, Run1, Attempt0, Delivery);
            {error, FailureClass, FailureSummary} ->
              finalize_run_failure(
                RootDir,
                CaseId,
                CaseDir,
                Task1,
                Run1,
                Attempt0,
                FailureClass,
                FailureSummary,
                FinalText
              )
          end;
        {error, FailureClass, FailureSummary} ->
          finalize_run_failure(
            RootDir,
            CaseId,
            CaseDir,
            Task1,
            Run1,
            Attempt0,
            FailureClass,
            FailureSummary,
            FinalText
          )
      end;
    {error, {runtime_error, Reason, _SessionId}} ->
      {FailureClass, FailureSummary} = classify_runtime_failure(Reason),
      finalize_run_failure(
        RootDir,
        CaseId,
        CaseDir,
        Task1,
        Run1,
        Attempt0,
        FailureClass,
        FailureSummary,
        undefined
      );
    {error, Reason} ->
      {FailureClass, FailureSummary} = classify_runtime_failure(Reason),
      finalize_run_failure(
        RootDir,
        CaseId,
        CaseDir,
        Task1,
        Run1,
        Attempt0,
        FailureClass,
        FailureSummary,
        undefined
      )
  end.

create_attempt_session(RootDir, CaseId, TaskId, RunId, AttemptId) ->
  {ok, SessionId0} =
    openagentic_session_store:create_session(
      RootDir,
      #{
        kind => <<"monitoring_run_attempt">>,
        case_id => CaseId,
        task_id => TaskId,
        run_id => RunId,
        attempt_id => AttemptId
      }
    ),
  to_bin(SessionId0).

append_attempt_start_event(RootDir, ExecutionSessionId, CaseId, TaskId, RunId, AttemptId) ->
  _ =
    catch
      openagentic_session_store:append_event(
        RootDir,
        ensure_list(ExecutionSessionId),
        #{
          type => <<"monitoring.attempt.started">>,
          case_id => CaseId,
          task_id => TaskId,
          run_id => RunId,
          attempt_id => AttemptId
        }
      ),
  ok.

build_monitoring_run(CaseId, TaskId, VersionId, RunId, Version, Input, Now) ->
  #{
    header => header(RunId, <<"monitoring_run">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          task_version_id => VersionId,
          pack_ids => [],
          latest_attempt_id => undefined,
          successful_attempt_id => undefined,
          report_id => undefined
        }
      ),
    spec =>
      compact_map(
        #{
          run_kind => get_bin(Input, [run_kind, runKind], <<"manual">>),
          trigger_type => get_bin(Input, [trigger_type, triggerType], <<"manual">>),
          trigger_ref => get_bin(Input, [trigger_ref, triggerRef], undefined),
          expected_outputs_contract_ref => <<VersionId/binary, "#report_contract">>,
          planned_for_at => get_number(Input, [planned_for_at, plannedForAt], Now),
          timezone => task_timezone(Version)
        }
      ),
    state =>
      #{
        status => <<"scheduled">>,
        attempt_count => 0,
        last_attempt_status => undefined,
        completed_at => undefined,
        result_summary => undefined,
        started_at => undefined
      },
    audit => compact_map(#{triggered_at => Now, triggered_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined)}),
    ext => #{}
  }.

build_run_attempt(
  CaseId,
  TaskId,
  RunId,
  AttemptId,
  PreviousAttemptId,
  ExecutionSessionId,
  ScratchRef,
  AttemptIndex,
  Input,
  ExecutionProfile,
  CredentialSnapshot,
  Now
) ->
  #{
    header => header(AttemptId, <<"run_attempt">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          run_id => RunId,
          previous_attempt_id => PreviousAttemptId,
          execution_session_id => ExecutionSessionId,
          scratch_ref => ScratchRef
        }
      ),
    spec =>
      compact_map(
        #{
          attempt_index => AttemptIndex,
          attempt_reason => get_bin(Input, [attempt_reason, attemptReason], default_attempt_reason(AttemptIndex)),
          execution_profile_snapshot => ExecutionProfile,
          strategy_note => get_bin(Input, [strategy_note, strategyNote], undefined),
          credential_resolution_snapshot => CredentialSnapshot
        }
      ),
    state =>
      #{
        status => <<"running">>,
        started_at => Now,
        ended_at => undefined,
        failure_class => undefined,
        failure_summary => undefined,
        promoted_artifact_refs => []
      },
    audit => compact_map(#{triggered_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined)}),
    ext => #{}
  }.

default_attempt_reason(1) -> <<"initial_execution">>;
default_attempt_reason(_) -> <<"retry_after_failure">>.

task_timezone(Version) ->
  SchedulePolicy = ensure_map(get_in_map(Version, [spec, schedule_policy], #{})),
  get_bin(SchedulePolicy, [timezone], <<"Asia/Shanghai">>).

build_execution_profile_snapshot(Input, Task, Version, AllowedTools, ScratchRef) ->
  RuntimeOpts = normalize_runtime_opts(ensure_map(get_in_map(Input, [runtime_opts], get_in_map(Input, [runtimeOpts], #{})))),
  ToolProfile = ensure_map(get_in_map(Version, [spec, tool_profile], #{})),
  compact_map(
    #{
      provider_mod => to_bin(find_any(RuntimeOpts, [provider_mod, providerMod])),
      model => find_any(RuntimeOpts, [model]),
      base_url => find_any(RuntimeOpts, [base_url, baseUrl]),
      allowed_tools => AllowedTools,
      tool_profile => ToolProfile,
      schedule_policy => get_in_map(Version, [spec, schedule_policy], #{}),
      permission_mode => maps:get(mode, ensure_map(find_any(RuntimeOpts, [permission_gate, permissionGate])), undefined),
      max_steps => find_any(RuntimeOpts, [max_steps, maxSteps]),
      task_workspace_ref => get_in_map(Task, [links, workspace_ref], undefined),
      scratch_ref => ScratchRef
    }
  ).

build_credential_resolution_snapshot(CredentialBindings0) ->
  CredentialBindings = [ensure_map(B) || B <- CredentialBindings0],
  Resolved =
    [
      compact_map(
        #{
          credential_binding_id => id_of(Binding),
          slot_name => get_in_map(Binding, [spec, slot_name], undefined),
          provider => get_in_map(Binding, [spec, provider], undefined),
          status => get_in_map(Binding, [state, status], undefined)
        }
      )
     || Binding <- CredentialBindings
    ],
  #{used_binding_ids => [id_of(Binding) || Binding <- CredentialBindings, binding_status_valid(Binding)], bindings => Resolved, fallback_used => false}.

resolve_allowed_tools(Version) ->
  ToolProfile = ensure_map(get_in_map(Version, [spec, tool_profile], #{})),
  case find_any(ToolProfile, [allowed_tools, allowedTools]) of
    undefined -> undefined;
    Value when is_list(Value) -> [to_bin(Item) || Item <- Value, trim_bin(to_bin(Item)) =/= <<>>];
    Value -> [to_bin(Value)]
  end.

build_monitoring_runtime_opts(RootDir, CaseDir, Task, ScratchDir, ExecutionSessionId, AllowedTools, Input) ->
  RuntimeOpts0 = ensure_map(get_in_map(Input, [runtime_opts], get_in_map(Input, [runtimeOpts], #{}))),
  RuntimeOpts1 = normalize_runtime_opts(RuntimeOpts0),
  TaskWorkspaceDir = task_workspace_dir(CaseDir, Task),
  BaseOpts =
    compact_map(
      #{
        session_root => RootDir,
        project_dir =>
          case find_any(RuntimeOpts1, [project_dir, projectDir]) of
            undefined -> RootDir;
            ProjectDir -> ProjectDir
          end,
        cwd =>
          case find_any(RuntimeOpts1, [cwd]) of
            undefined -> TaskWorkspaceDir;
            Cwd -> Cwd
          end,
        resume_session_id => ExecutionSessionId,
        workspace_dir => TaskWorkspaceDir,
        scratch_dir => ScratchDir,
        tools =>
          case find_any(RuntimeOpts1, [tools]) of
            undefined -> [];
            ToolMods -> ToolMods
          end,
        permission_gate =>
          case find_any(RuntimeOpts1, [permission_gate, permissionGate]) of
            undefined -> openagentic_permissions:default(undefined);
            PermissionGate -> PermissionGate
          end,
        allowed_tools => AllowedTools,
        strict_unknown_fields => true
      }
    ),
  maps:merge(RuntimeOpts1, BaseOpts).

normalize_runtime_opts(RuntimeOpts0) ->
  RuntimeOpts = ensure_map(RuntimeOpts0),
  case find_any(RuntimeOpts, [provider_mod, providerMod]) of
    undefined -> RuntimeOpts;
    ProviderMod -> RuntimeOpts#{provider_mod => normalize_provider_mod(ProviderMod)}
  end.

normalize_provider_mod(ProviderMod) when is_atom(ProviderMod) -> ProviderMod;
normalize_provider_mod(ProviderMod) ->
  ProviderModBin = trim_bin(to_bin(ProviderMod)),
  case ProviderModBin of
    <<>> -> ProviderMod;
    _ ->
      try binary_to_existing_atom(ProviderModBin, utf8) of
        Mod -> Mod
      catch
        error:badarg -> ProviderMod
      end
  end.

build_monitoring_prompt(Task, Version, Attempt, RunContext0) ->
  RunContext = ensure_map(RunContext0),
  TaskPayload =
    #{
      task_id => id_of(Task),
      title => get_in_map(Task, [spec, title], <<>>),
      mission_statement => get_in_map(Task, [spec, mission_statement], <<>>),
      task_version_id => id_of(Version),
      objective => get_in_map(Version, [spec, objective], <<>>),
      schedule_policy => get_in_map(Version, [spec, schedule_policy], #{}),
      report_contract => get_in_map(Version, [spec, report_contract], #{}),
      attempt_id => id_of(Attempt),
      attempt_index => get_in_map(Attempt, [spec, attempt_index], 1),
      task_workspace_ref => get_in_map(Task, [links, workspace_ref], <<>>),
      scratch_ref => get_in_map(Attempt, [links, scratch_ref], <<>>),
      credential_resolution_snapshot => get_in_map(Attempt, [spec, credential_resolution_snapshot], #{}),
      run_context => RunContext
    },
  Payload = openagentic_json:encode_safe(TaskPayload),
  iolist_to_binary(
    [
      <<"You are the monitoring officer for one monitoring task. Execute one unattended monitoring run and return exactly one JSON object, with no prose outside JSON.\n\n">>,
      <<"Required top-level fields: report_markdown (string), facts (array), artifacts (array). Optional: result_summary, alert_summary, report_kind, observed_window.\n">>,
      <<"facts[] should include: title, fact_type, source or source_url, collection_method, value_summary, change_summary, alert_level, confidence_note, evidence_refs.\n">>,
      <<"At least one fact must contain a traceable source reference via source_url or evidence_refs.\n">>,
      <<"Task context JSON:\n">>,
      Payload,
      <<"\n">>
    ]
  ).

parse_monitoring_delivery(Output0, TaskId, RunId, Now) ->
  case parse_json_object(Output0) of
    {error, _} ->
      {error, <<"report_quality_insufficient">>, <<"monitoring delivery must be one JSON object">>};
    {ok, Obj0} ->
      Obj = ensure_map(Obj0),
      ReportMarkdown = trim_bin(get_bin(Obj, [report_markdown, reportMarkdown], <<>>)),
      Facts0 = get_list(Obj, [facts], []),
      Artifacts0 = get_list(Obj, [artifacts], []),
      case {byte_size(ReportMarkdown) > 0, is_list(Facts0), is_list(Artifacts0)} of
        {true, true, true} ->
          Facts = normalize_monitoring_facts(Facts0, TaskId, RunId, Now),
          case has_traceable_source(Facts) of
            false ->
              {error, <<"report_quality_insufficient">>, <<"facts.json requires at least one traceable source reference">>};
            true ->
              {ok,
               #{
                 report_markdown => ReportMarkdown,
                 facts => Facts,
                 artifacts => normalize_monitoring_artifacts(Artifacts0, Now),
                 result_summary => get_bin(Obj, [result_summary, resultSummary], <<"monitoring run completed">>),
                 alert_summary => get_bin(Obj, [alert_summary, alertSummary], undefined),
                 report_kind => get_bin(Obj, [report_kind, reportKind], <<"routine_fact_report">>),
                 observed_window => normalize_observed_window(choose_map(Obj, [observed_window, observedWindow], #{}), Facts, Now)
               }}
          end;
        _ ->
          {error, <<"report_quality_insufficient">>, <<"monitoring delivery missing report_markdown/facts/artifacts">>}
      end
  end.

normalize_monitoring_facts(Facts0, TaskId, RunId, Now) ->
  normalize_monitoring_facts(Facts0, TaskId, RunId, Now, []).

normalize_monitoring_facts([], _TaskId, _RunId, _Now, Acc) ->
  lists:reverse(Acc);
normalize_monitoring_facts([Fact0 | Rest], TaskId, RunId, Now, Acc) ->
  Fact = ensure_map(Fact0),
  SourceUrl = get_bin(Fact, [source_url, sourceUrl, url], undefined),
  EvidenceRefs0 = get_list(Fact, [evidence_refs, evidenceRefs], []),
  EvidenceRefs =
    case {EvidenceRefs0, SourceUrl} of
      {[], Url} when is_binary(Url), Url =/= <<>> -> [#{kind => <<"url">>, ref => Url}];
      _ -> normalize_evidence_refs(EvidenceRefs0)
    end,
  ValueSummary = get_bin(Fact, [value_summary, valueSummary], <<>>),
  Title =
    case get_bin(Fact, [title], undefined) of
      undefined when ValueSummary =/= <<>> -> ValueSummary;
      undefined -> <<"Fact">>;
      Value -> Value
    end,
  Fact1 =
    compact_map(
      #{
        fact_id => get_bin(Fact, [fact_id, factId], new_id(<<"fact">>)),
        task_id => TaskId,
        run_id => RunId,
        observed_at => get_number(Fact, [observed_at, observedAt], Now),
        collected_at => get_number(Fact, [collected_at, collectedAt], Now),
        title => Title,
        fact_type => get_bin(Fact, [fact_type, factType], <<"observation">>),
        source => get_bin(Fact, [source], get_bin(Fact, [source_name, sourceName], undefined)),
        source_url => SourceUrl,
        collection_method => get_bin(Fact, [collection_method, collectionMethod], <<"agent_monitoring">>),
        value_summary => ValueSummary,
        change_summary => get_bin(Fact, [change_summary, changeSummary], <<>>),
        alert_level => get_bin(Fact, [alert_level, alertLevel], <<"normal">>),
        confidence_note => get_bin(Fact, [confidence_note, confidenceNote], <<"not_provided">>),
        evidence_refs => EvidenceRefs
      }
    ),
  normalize_monitoring_facts(Rest, TaskId, RunId, Now, [Fact1 | Acc]).

normalize_evidence_refs(Refs0) ->
  lists:map(
    fun (Ref0) when is_binary(Ref0); is_list(Ref0) -> #{kind => <<"text">>, ref => trim_bin(to_bin(Ref0))};
        (Ref0) ->
      Ref = ensure_map(Ref0),
      compact_map(#{kind => get_bin(Ref, [kind], <<"text">>), ref => get_bin(Ref, [ref, value, url], undefined)})
    end,
    ensure_list(Refs0)
  ).

normalize_monitoring_artifacts(Artifacts0, Now) ->
  normalize_monitoring_artifacts(Artifacts0, Now, []).

normalize_monitoring_artifacts([], _Now, Acc) ->
  lists:reverse(Acc);
normalize_monitoring_artifacts([Artifact0 | Rest], Now, Acc) ->
  Artifact = ensure_map_or_path(Artifact0),
  Path = get_bin(Artifact, [path, url, source_url], undefined),
  Title =
    case get_bin(Artifact, [title], undefined) of
      undefined when Path =/= undefined -> Path;
      undefined -> <<"artifact">>;
      Value -> Value
    end,
  Artifact1 =
    compact_map(
      #{
        artifact_id => get_bin(Artifact, [artifact_id, artifactId], new_id(<<"artifact">>)),
        title => Title,
        kind => get_bin(Artifact, [kind], <<"attachment">>),
        summary => get_bin(Artifact, [summary], undefined),
        path => Path,
        created_at => get_number(Artifact, [created_at, createdAt], Now)
      }
    ),
  normalize_monitoring_artifacts(Rest, Now, [Artifact1 | Acc]).

ensure_map_or_path(Value) when is_map(Value) -> Value;
ensure_map_or_path(Value) when is_binary(Value); is_list(Value) -> #{path => to_bin(Value)};
ensure_map_or_path(Value) -> ensure_map(Value).

normalize_observed_window(Window0, Facts, Now) ->
  Window = ensure_map(Window0),
  StartedAt =
    case get_number(Window, [started_at, startedAt], undefined) of
      undefined -> infer_fact_time(Facts, observed_at, Now);
      StartedValue -> StartedValue
    end,
  EndedAt =
    case get_number(Window, [ended_at, endedAt], undefined) of
      undefined -> infer_fact_time(Facts, collected_at, Now);
      EndedValue -> EndedValue
    end,
  #{started_at => StartedAt, ended_at => EndedAt}.

infer_fact_time([], _Field, Default) -> Default;
infer_fact_time(Facts, Field, Default) ->
  Values = [maps:get(Field, Fact, Default) || Fact <- Facts, maps:get(Field, Fact, undefined) =/= undefined],
  case Values of
    [] -> Default;
    _ when Field =:= observed_at -> lists:min(Values);
    _ -> lists:max(Values)
  end.

has_traceable_source(Facts) ->
  lists:any(
    fun (Fact) ->
      SourceUrl = get_bin(Fact, [source_url, sourceUrl], <<>>),
      EvidenceRefs = get_list(Fact, [evidence_refs, evidenceRefs], []),
      SourceUrl =/= <<>> orelse EvidenceRefs =/= []
    end,
    Facts
  ).

parse_json_object(Output0) ->
  Output = string:trim(to_bin(Output0)),
  Bin = strip_json_code_fences(Output),
  try
    Obj = openagentic_json:decode(Bin),
    case is_map(Obj) of
      true -> {ok, normalize_keys(Obj)};
      false -> {error, not_object}
    end
  catch
    _:_ -> {error, invalid_json}
  end.

strip_json_code_fences(Bin0) ->
  Bin = to_bin(Bin0),
  case re:run(Bin, <<"(?s)^```[a-zA-Z0-9_-]*\\s*(\\{.*\\})\\s*```\\s*$">>, [{capture, [1], binary}, unicode]) of
    {match, [Inner]} -> Inner;
    _ -> Bin
  end.

finalize_run_success(RootDir, CaseId, CaseDir, Task0, Version, Run0, Attempt0, Delivery0) ->
  Delivery = ensure_map(Delivery0),
  Now = now_ts(),
  TaskId = id_of(Task0),
  RunId = id_of(Run0),
  AttemptId = id_of(Attempt0),
  ScratchDir = filename:join([CaseDir, ensure_list(get_in_map(Attempt0, [links, scratch_ref], <<>>))]),
  ok = write_attempt_delivery_files(ScratchDir, Delivery),
  ArtifactRefs = promote_attempt_delivery(CaseDir, TaskId, RunId, AttemptId, Delivery, Now),
  PreviousReports = lists:reverse(read_task_fact_reports(CaseDir, TaskId)),
  ReportId = new_id(<<"report">>),
  {SupersedesReportId, ReportLineageId} =
    case PreviousReports of
      [PreviousReport | _] ->
        PrevLineageId = get_in_map(PreviousReport, [ext, report_lineage_id], id_of(PreviousReport)),
        {id_of(PreviousReport), PrevLineageId};
      [] ->
        {undefined, ReportId}
    end,
  ReportsToSupersede =
    case PreviousReports of
      [PreviousReport0 | _] -> [PreviousReport0];
      [] -> []
    end,
  lists:foreach(
    fun (PreviousReport0) ->
      PreviousReport1 =
        update_object(
          ensure_map(PreviousReport0),
          Now,
          fun (Obj) ->
            Obj#{ext => maps:merge(maps:get(ext, Obj, #{}), #{superseded_by_report_id => ReportId})}
          end
        ),
      ok = persist_case_object(CaseDir, fact_report_file(CaseDir, TaskId, id_of(PreviousReport1)), PreviousReport1)
    end,
    ReportsToSupersede
  ),
  FactReport =
    build_fact_report(
      CaseId,
      TaskId,
      RunId,
      AttemptId,
      id_of(Version),
      ReportId,
      Delivery,
      ArtifactRefs,
      SupersedesReportId,
      ReportLineageId,
      Now
    ),
  ok = persist_case_object(CaseDir, fact_report_file(CaseDir, TaskId, ReportId), FactReport),
  Attempt1 =
    update_object(
      Attempt0,
      Now,
      fun (Obj) ->
        Obj#{
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"succeeded">>, ended_at => Now, promoted_artifact_refs => [id_of(Artifact) || Artifact <- ArtifactRefs]}
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, run_attempt_file(CaseDir, TaskId, AttemptId), Attempt1),
  Run1 =
    update_object(
      Run0,
      Now,
      fun (Obj) ->
        RunStatus =
          case delivery_needs_followup(Delivery) of
            true -> <<"needs_followup">>;
            false -> <<"report_submitted">>
          end,
        Obj#{
          links => maps:merge(maps:get(links, Obj, #{}), #{latest_attempt_id => AttemptId, successful_attempt_id => AttemptId, report_id => ReportId}),
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{
                status => RunStatus,
                attempt_count => get_in_map(Attempt1, [spec, attempt_index], 1),
                last_attempt_status => <<"succeeded">>,
                completed_at => Now,
                result_summary => get_bin(Delivery, [result_summary], <<"monitoring run completed">>)
              }
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, run_file(CaseDir, TaskId, RunId), Run1),
  Task1 =
    update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"active">>, health => <<"healthy">>, latest_run_id => RunId, latest_successful_run_id => RunId, last_report_at => Now}
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, task_file(CaseDir, TaskId), Task1),
  ok = refresh_case_state(RootDir, CaseId),
  ok = rebuild_indexes(RootDir, CaseId),
  {ok, #{task => Task1, run => Run1, run_attempt => Attempt1, fact_report => FactReport, overview => get_case_overview_map(RootDir, CaseId)}}.

finalize_run_failure(RootDir, CaseId, CaseDir, Task0, Run0, Attempt0, FailureClass, FailureSummary0, RawOutput) ->
  Now = now_ts(),
  TaskId = id_of(Task0),
  RunId = id_of(Run0),
  AttemptId = id_of(Attempt0),
  ScratchDir = filename:join([CaseDir, ensure_list(get_in_map(Attempt0, [links, scratch_ref], <<>>))]),
  FailureSummary = trim_bin(to_bin(FailureSummary0)),
  ok = maybe_write_failure_output(ScratchDir, RawOutput, FailureSummary),
  Attempt1 =
    update_object(
      Attempt0,
      Now,
      fun (Obj) ->
        Obj#{
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"failed">>, ended_at => Now, failure_class => FailureClass, failure_summary => FailureSummary, promoted_artifact_refs => []}
            )
        }
      end
    ),
  ok = persist_case_object(CaseDir, run_attempt_file(CaseDir, TaskId, AttemptId), Attempt1),
  Run1 =
    update_object(
      Run0,
      Now,
      fun (Obj) ->
        Obj#{
          links => maps:merge(maps:get(links, Obj, #{}), #{latest_attempt_id => AttemptId}),
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"failed">>, attempt_count => get_in_map(Attempt1, [spec, attempt_index], 1), last_attempt_status => <<"failed">>, completed_at => Now, result_summary => FailureSummary}
            ),
          audit => maps:merge(maps:get(audit, Obj, #{}), #{failure_class => FailureClass, failure_summary => FailureSummary})
        }
      end
    ),
  ok = persist_case_object(CaseDir, run_file(CaseDir, TaskId, RunId), Run1),
  ExceptionBrief = build_exception_brief(CaseId, Task0, Run1, Attempt1, FailureClass, FailureSummary, Now),
  FailureMail = build_task_run_failure_mail(CaseId, Task0, Run1, Attempt1, ExceptionBrief, FailureClass, FailureSummary, Now),
  {TaskStatus, TaskHealth, RectificationMail} = derive_task_failure_outcome(CaseDir, Task0, Now),
  Task1 =
    update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{
          state => maps:merge(maps:get(state, Obj, #{}), #{status => TaskStatus, health => TaskHealth, latest_run_id => RunId})
        }
      end
    ),
  ok = persist_case_object(CaseDir, task_file(CaseDir, TaskId), Task1),
  ok = persist_case_object(CaseDir, exception_brief_file(CaseDir, TaskId, id_of(ExceptionBrief)), ExceptionBrief),
  ok = maybe_persist_mail(CaseDir, FailureMail),
  ok = maybe_persist_mail(CaseDir, RectificationMail),
  ok = refresh_case_state(RootDir, CaseId),
  ok = rebuild_indexes(RootDir, CaseId),
  Base =
    #{
      task => Task1,
      run => Run1,
      run_attempt => Attempt1,
      exception_brief => ExceptionBrief,
      mail => FailureMail,
      overview => get_case_overview_map(RootDir, CaseId)
    },
  case RectificationMail of
    undefined -> {ok, Base};
    _ -> {ok, Base#{rectification_mail => RectificationMail}}
  end.

maybe_write_failure_output(ScratchDir, RawOutput, FailureSummary) ->
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  case RawOutput of
    undefined -> file:write_file(filename:join([ScratchDir, "failure.txt"]), <<FailureSummary/binary, "\n">>);
    <<>> -> file:write_file(filename:join([ScratchDir, "failure.txt"]), <<FailureSummary/binary, "\n">>);
    Bin -> file:write_file(filename:join([ScratchDir, "raw-output.txt"]), <<(to_bin(Bin))/binary, "\n">>)
  end,
  ok.

write_attempt_delivery_files(ScratchDir, Delivery) ->
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  ok = file:write_file(filename:join([ScratchDir, "report.md"]), <<(get_bin(Delivery, [report_markdown], <<>>))/binary, "\n">>),
  FactsBody = openagentic_json:encode_safe(#{facts => maps:get(facts, Delivery, [])}),
  ArtifactsBody = openagentic_json:encode_safe(#{artifacts => maps:get(artifacts, Delivery, [])}),
  ok = file:write_file(filename:join([ScratchDir, "facts.json"]), <<FactsBody/binary, "\n">>),
  ok = file:write_file(filename:join([ScratchDir, "artifacts.json"]), <<ArtifactsBody/binary, "\n">>).

promote_attempt_delivery(CaseDir, TaskId, RunId, AttemptId, Delivery, Now) ->
  DeliverDir = deliverables_dir(CaseDir, TaskId, RunId),
  ok = filelib:ensure_dir(filename:join([DeliverDir, "x"])),
  ScratchDir = filename:join([CaseDir, ensure_list(attempt_scratch_ref(TaskId, RunId, AttemptId))]),
  ok = copy_if_exists(filename:join([ScratchDir, "report.md"]), filename:join([DeliverDir, "report.md"])),
  ok = copy_if_exists(filename:join([ScratchDir, "facts.json"]), filename:join([DeliverDir, "facts.json"])),
  ExternalArtifacts = maps:get(artifacts, Delivery, []),
  ExternalRefs = build_external_artifact_refs(TaskId, RunId, AttemptId, ExternalArtifacts, Now),
  BaseRefs =
    [
      build_promoted_artifact(TaskId, RunId, AttemptId, <<"report.md">>, <<"report_markdown">>, <<"Human-readable monitoring report">>, Now),
      build_promoted_artifact(TaskId, RunId, AttemptId, <<"facts.json">>, <<"facts_json">>, <<"Structured facts payload">>, Now)
    ],
  IndexRefs = BaseRefs ++ ExternalRefs,
  ArtifactsIndexBody = openagentic_json:encode_safe(#{artifacts => IndexRefs}),
  ok = file:write_file(filename:join([DeliverDir, "artifacts.json"]), <<ArtifactsIndexBody/binary, "\n">>),
  BaseRefs ++ [build_promoted_artifact(TaskId, RunId, AttemptId, <<"artifacts.json">>, <<"artifact_index">>, <<"Formal artifact index">>, Now)] ++ ExternalRefs.

copy_if_exists(Src, Dest) ->
  case filelib:is_file(Src) of
    true ->
      case file:copy(Src, Dest) of
        {ok, _} -> ok;
        ok -> ok;
        _ -> ok
      end;
    false -> ok
  end.

build_promoted_artifact(TaskId, RunId, AttemptId, FileName, Kind, Summary, Now) ->
  RelPath = deliverable_ref(TaskId, RunId, FileName),
  #{
    header => header(new_id(<<"artifact">>), <<"run_artifact">>, Now),
    links => compact_map(#{task_id => TaskId, run_id => RunId, source_attempt_id => AttemptId}),
    spec => #{title => FileName, kind => Kind, summary => Summary, path => RelPath},
    state => #{status => <<"promoted">>},
    audit => #{},
    ext => #{}
  }.

build_external_artifact_refs(TaskId, RunId, AttemptId, Artifacts0, Now) ->
  lists:map(
    fun(Artifact0) ->
      Artifact = ensure_map(Artifact0),
      # {
        header => header(new_id(<<"artifact">>), <<"run_artifact">>, Now),
        links => compact_map(#{task_id => TaskId, run_id => RunId, source_attempt_id => AttemptId}),
        spec => compact_map(#{title => get_bin(Artifact, [title], <<"artifact">>), kind => get_bin(Artifact, [kind], <<"attachment">>), summary => get_bin(Artifact, [summary], undefined), path => get_bin(Artifact, [path], undefined)}),
        state => #{status => <<"indexed">>},
        audit => #{},
        ext => #{}
      }
    end,
    Artifacts0
  ).

build_fact_report(CaseId, TaskId, RunId, AttemptId, VersionId, ReportId, Delivery, ArtifactRefs, SupersedesReportId, ReportLineageId, Now) ->
  #{
    header => header(ReportId, <<"fact_report">>, Now),
    links => compact_map(#{case_id => CaseId, task_id => TaskId, run_id => RunId, successful_attempt_id => AttemptId, pack_ids => []}),
    spec => compact_map(#{report_contract_ref => <<VersionId/binary, "#report_contract">>, artifact_refs => ArtifactRefs, observed_window => get_in_map(Delivery, [observed_window], #{}), report_kind => get_bin(Delivery, [report_kind], <<"routine_fact_report">>)}),
    state => compact_map(#{status => <<"submitted">>, submitted_at => Now, accepted_at => undefined, quality_summary => get_bin(Delivery, [result_summary], undefined), alert_summary => get_bin(Delivery, [alert_summary], undefined)}),
    audit => #{},
    ext => #{report_lineage_id => ReportLineageId, supersedes_report_id => SupersedesReportId, superseded_by_report_id => undefined}
  }.

derive_task_failure_outcome(CaseDir, Task0, Now) ->
  TaskId = id_of(Task0),
  Runs = lists:reverse(read_task_runs(CaseDir, TaskId)),
  Attempts = read_task_run_attempts(CaseDir, TaskId),
  Count = consecutive_failure_count(Runs, Attempts),
  LatestFailureClass = latest_failure_class(Attempts),
  CurrentStatus = get_in_map(Task0, [state, status], <<"active">>),
  case Count >= 3 of
    true ->
      MailObj =
        case CurrentStatus of
          <<"rectification_required">> -> undefined;
          _ -> build_rectification_mail(get_in_map(Task0, [links, case_id], undefined), Task0, LatestFailureClass, Count, Now)
        end,
      {<<"rectification_required">>, <<"rectification_required">>, MailObj};
    false when Count =:= 2 -> {<<"active">>, <<"flaky">>, undefined};
    false -> {<<"active">>, <<"degraded">>, undefined}
  end.

consecutive_failure_count(Runs0, Attempts0) ->
  Runs = [ensure_map(R) || R <- Runs0],
  Attempts = [ensure_map(A) || A <- Attempts0],
  consecutive_failure_count(Runs, Attempts, 0).

consecutive_failure_count([], _Attempts, Acc) -> Acc;
consecutive_failure_count([Run | Rest], Attempts, Acc) ->
  LatestAttemptId = get_in_map(Run, [links, latest_attempt_id], undefined),
  case find_attempt(Attempts, LatestAttemptId) of
    undefined -> Acc;
    Attempt ->
      case get_in_map(Attempt, [state, status], <<>>) of
        <<"failed">> -> consecutive_failure_count(Rest, Attempts, Acc + 1);
        _ -> Acc
      end
  end.

latest_failure_class(Attempts0) ->
  Attempts = lists:reverse([ensure_map(Attempt) || Attempt <- Attempts0]),
  case [get_in_map(Attempt, [state, failure_class], undefined) || Attempt <- Attempts, get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>] of
    [FailureClass | _] -> FailureClass;
    [] -> undefined
  end.

find_attempt([], _AttemptId) -> undefined;
find_attempt([Attempt | Rest], AttemptId) ->
  case id_of(Attempt) =:= AttemptId of
    true -> Attempt;
    false -> find_attempt(Rest, AttemptId)
  end.

build_rectification_mail(CaseId, Task0, FailureClass, Count, Now) ->
  TaskId = id_of(Task0),
  Title = get_in_map(Task0, [spec, title], <<"Untitled Task">>),
  MailId = new_id(<<"mail">>),
  #{
    header => header(MailId, <<"internal_mail">>, Now),
    links => compact_map(#{case_id => CaseId, related_object_refs => [#{type => <<"monitoring_task">>, id => TaskId}], source_op_id => undefined, source_session_id => undefined}),
    spec => #{message_type => <<"task_rectification_required">>, title => <<"task rectification required">>, summary => Title, recommended_action => <<"rectify_task">>, available_actions => [<<"review">>], failure_class => FailureClass, failure_count => Count},
    state => #{status => <<"unread">>, severity => <<"high">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

maybe_persist_mail(_CaseDir, undefined) -> ok;
maybe_persist_mail(CaseDir, MailObj) -> persist_case_object(CaseDir, mail_file(CaseDir, id_of(MailObj)), MailObj).

revise_task_with_session(RootDir, CaseId, CaseDir, Task0, Input, GovernanceSessionId) ->
  TaskId = get_in_map(Task0, [header, id], <<>>),
  case lists:reverse(read_task_versions(CaseDir, TaskId)) of
    [] ->
      {error, no_task_version};
    [CurrentVersion0 | _] ->
      Now = now_ts(),
      CurrentVersionId = id_of(CurrentVersion0),
      NextVersionId = new_id(<<"version">>),
      CurrentVersion1 =
        update_object(
          CurrentVersion0,
          Now,
          fun (Obj) ->
            Obj#{
              state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"superseded">>, superseded_at => Now})
            }
          end
        ),
      NextVersion = build_revised_task_version(CaseId, TaskId, NextVersionId, CurrentVersion0, Input, GovernanceSessionId, Now),
      ok = persist_case_object(CaseDir, task_version_file(CaseDir, TaskId, CurrentVersionId), CurrentVersion1),
      ok = persist_case_object(CaseDir, task_version_file(CaseDir, TaskId, NextVersionId), NextVersion),
      Task1Base =
        update_object(
          Task0,
          Now,
          fun (Obj) ->
            Obj#{
              links => maps:merge(maps:get(links, Obj, #{}), #{active_version_id => NextVersionId}),
              audit =>
                maps:merge(
                  maps:get(audit, Obj, #{}),
                  compact_map(
                    #{
                      revised_at => Now,
                      revised_by_op_id => get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
                      latest_governance_session_id => GovernanceSessionId,
                      latest_change_summary => get_bin(Input, [change_summary, changeSummary], undefined)
                    }
                  )
                )
            }
          end
        ),
      {Task1, Authorization} = sync_task_authorization(CaseDir, Task1Base, Now),
      ok = refresh_case_state(RootDir, CaseId),
      ok = rebuild_indexes(RootDir, CaseId),
      ok = append_governance_revision_event(RootDir, GovernanceSessionId, CaseId, TaskId, CurrentVersionId, NextVersionId, Input),
      {ok,
       #{
         task => Task1,
         task_version => NextVersion,
         authorization => Authorization,
         latest_version_diff => build_latest_version_diff(read_task_versions(CaseDir, TaskId), Authorization),
         overview => get_case_overview_map(RootDir, CaseId)
       }}
  end.

build_revised_task_version(CaseId, TaskId, VersionId, CurrentVersion0, Input, GovernanceSessionId, Now) ->
  CurrentVersion = ensure_map(CurrentVersion0),
  CurrentLinks = ensure_map(maps:get(links, CurrentVersion, #{})),
  CurrentSpec = ensure_map(maps:get(spec, CurrentVersion, #{})),
  #{
    header => header(VersionId, <<"task_version">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          previous_version_id => id_of(CurrentVersion),
          derived_from_template_ref =>
            get_bin(Input, [derived_from_template_ref, derivedFromTemplateRef], get_in_map(CurrentLinks, [derived_from_template_ref], undefined)),
          approved_by_op_id =>
            get_bin(
              Input,
              [approved_by_op_id, approvedByOpId],
              get_bin(Input, [revised_by_op_id, revisedByOpId], get_in_map(CurrentLinks, [approved_by_op_id], undefined))
            )
        }
      ),
    spec =>
      compact_map(
        #{
          objective => get_bin(Input, [objective], get_in_map(CurrentSpec, [objective], <<>>)),
          schedule_policy => choose_map(Input, [schedule_policy, schedulePolicy], get_in_map(CurrentSpec, [schedule_policy], #{})),
          report_contract => choose_map(Input, [report_contract, reportContract], get_in_map(CurrentSpec, [report_contract], #{})),
          alert_rules => choose_map(Input, [alert_rules, alertRules], get_in_map(CurrentSpec, [alert_rules], #{})),
          source_strategy => choose_map(Input, [source_strategy, sourceStrategy], get_in_map(CurrentSpec, [source_strategy], #{})),
          tool_profile => choose_map(Input, [tool_profile, toolProfile], get_in_map(CurrentSpec, [tool_profile], #{})),
          credential_requirements =>
            choose_map(Input, [credential_requirements, credentialRequirements], get_in_map(CurrentSpec, [credential_requirements], #{})),
          autonomy_policy => choose_map(Input, [autonomy_policy, autonomyPolicy], get_in_map(CurrentSpec, [autonomy_policy], #{})),
          promotion_policy => choose_map(Input, [promotion_policy, promotionPolicy], get_in_map(CurrentSpec, [promotion_policy], #{}))
        }
      ),
    state => #{status => <<"active">>, activated_at => Now, superseded_at => undefined},
    audit =>
      compact_map(
        #{
          change_summary => get_bin(Input, [change_summary, changeSummary], <<"revise task version">>),
          approval_summary => get_bin(Input, [approval_summary, approvalSummary], undefined),
          revised_by_op_id => get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
          governance_session_id => GovernanceSessionId
        }
      ),
    ext => #{}
  }.

append_governance_revision_event(RootDir, GovernanceSessionId, CaseId, TaskId, PreviousVersionId, VersionId, Input) ->
  Event =
    compact_map(
      #{
        type => <<"governance.task_version.created">>,
        case_id => CaseId,
        task_id => TaskId,
        governance_session_id => GovernanceSessionId,
        previous_version_id => PreviousVersionId,
        task_version_id => VersionId,
        revised_by_op_id => get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
        change_summary => get_bin(Input, [change_summary, changeSummary], undefined),
        objective => get_bin(Input, [objective], undefined)
      }
    ),
  case catch openagentic_session_store:append_event(RootDir, ensure_list(GovernanceSessionId), Event) of
    {ok, _} -> ok;
    _ -> ok
  end.
create_candidates_and_mail(_RootDir, _CaseDir, _CaseId, _RoundId, _WorkflowSessionId, [], _Now) -> {[], []};
create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, [Spec | Rest], Now) ->
  CandidateId = new_id(<<"candidate">>),
  {ok, ReviewSessionId0} =
    openagentic_session_store:create_session(
      RootDir,
      #{kind => <<"candidate_review">>, case_id => CaseId, round_id => RoundId, candidate_id => CandidateId}
    ),
  ReviewSessionId = to_bin(ReviewSessionId0),
  CandidateObj = build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, Spec, Now),
  MailId = new_id(<<"mail">>),
  MailObj = build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now),
  ok = persist_case_object(CaseDir, candidate_file(CaseDir, CandidateId), CandidateObj),
  ok = persist_case_object(CaseDir, mail_file(CaseDir, MailId), MailObj),
  {RestCandidates, RestMail} = create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, Rest, Now),
  {[CandidateObj | RestCandidates], [MailObj | RestMail]}.

build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, Spec0, Now) ->
  Spec = ensure_map(Spec0),
  #{
    header => header(CandidateId, <<"monitoring_candidate">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          source_round_id => RoundId,
          review_session_id => ReviewSessionId,
          approved_task_id => undefined
        }
      ),
    spec =>
      compact_map(
        #{
          title => get_bin(Spec, [title], <<"Untitled Candidate">>),
          display_code => get_bin(Spec, [display_code, displayCode], display_code(<<"CAND">>)),
          mission_statement => get_bin(Spec, [mission_statement, missionStatement], get_bin(Spec, [objective], <<>>)),
          objective => get_bin(Spec, [objective], get_bin(Spec, [mission_statement, missionStatement], <<>>)),
          default_timezone => get_bin(Spec, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>),
          schedule_policy => choose_map(Spec, [schedule_policy, schedulePolicy], default_schedule_policy(get_bin(Spec, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>))),
          report_contract => choose_map(Spec, [report_contract, reportContract], default_report_contract()),
          alert_rules => choose_map(Spec, [alert_rules, alertRules], #{}),
          source_strategy => choose_map(Spec, [source_strategy, sourceStrategy], #{}),
          tool_profile => choose_map(Spec, [tool_profile, toolProfile], #{}),
          credential_requirements => choose_map(Spec, [credential_requirements, credentialRequirements], #{}),
          autonomy_policy => choose_map(Spec, [autonomy_policy, autonomyPolicy], #{}),
          promotion_policy => choose_map(Spec, [promotion_policy, promotionPolicy], #{}),
          template_ref => get_bin(Spec, [template_ref, templateRef], undefined),
          extracted_summary => get_bin(Spec, [extracted_summary, extractedSummary], undefined)
        }
      ),
    state => #{status => <<"inbox_pending">>, extracted_at => Now},
    audit =>
      compact_map(
        #{
          extracted_from_session_id => WorkflowSessionId,
          extracted_by_role => <<"proposer">>,
          extracted_at => Now
        }
      ),
    ext => #{}
  }.

build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now) ->
  Title = get_in_map(CandidateObj, [spec, title], <<"Untitled Candidate">>),
  #{
    header => header(MailId, <<"internal_mail">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          related_object_refs => [#{type => <<"monitoring_candidate">>, id => CandidateId}],
          source_op_id => undefined,
          source_session_id => WorkflowSessionId
        }
      ),
    spec =>
      #{
        message_type => <<"candidate_review_required">>,
        title => <<"candidate review pending">>,
        summary => Title,
        recommended_action => <<"review_candidate">>,
        available_actions => [<<"approve">>, <<"discard">>]
      },
    state => #{status => <<"unread">>, severity => <<"normal">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"proposer">>},
    ext => #{}
  }.

template_candidate_spec(TemplateObj0, Input0, CaseObj) ->
  TemplateObj = ensure_map(TemplateObj0),
  Input = ensure_map(Input0),
  TemplateSpec = ensure_map(maps:get(spec, TemplateObj, #{})),
  TemplateSummary = get_bin(TemplateSpec, [summary], undefined),
  DefaultTimezone = get_bin(TemplateSpec, [default_timezone, defaultTimezone], default_timezone(CaseObj)),
  maps:merge(
    TemplateSpec,
    compact_map(
      #{
        title => get_bin(Input, [title], get_in_map(TemplateSpec, [title], <<"Untitled Candidate">>)),
        objective => get_bin(Input, [objective], get_in_map(TemplateSpec, [objective], undefined)),
        default_timezone => get_bin(Input, [default_timezone, defaultTimezone], DefaultTimezone),
        extracted_summary => get_bin(Input, [summary], TemplateSummary)
      }
    )
  ).

decorate_global_mail(Mail0, CaseObj) ->
  Mail = ensure_map(Mail0),
  Ext0 = ensure_map(maps:get(ext, Mail, #{})),
  Mail#{
    ext =>
      maps:merge(
        Ext0,
        compact_map(
          #{
            case_title => get_in_map(CaseObj, [spec, title], undefined),
            case_display_code => get_in_map(CaseObj, [spec, display_code], undefined)
          }
        )
      )
  }.

update_mail_status(Mail0, Input0, Status, Now) ->
  Mail = ensure_map(Mail0),
  Input = ensure_map(Input0),
  update_object(
    Mail,
    Now,
    fun (Obj) ->
      Obj#{
        state =>
          maps:merge(
            maps:get(state, Obj, #{}),
            compact_map(
              #{
                status => Status,
                acted_at => Now,
                consumed_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined)
              }
            )
          ),
        audit =>
          maps:merge(
            maps:get(audit, Obj, #{}),
            compact_map(#{updated_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined)})
          )
      }
    end
  ).

get_case_overview_map(RootDir, CaseId) ->
  {ok, CaseObj, CaseDir} = load_case(RootDir, CaseId),
  Rounds = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  Candidates = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"]))),
  Tasks = sort_by_created_at(read_task_objects(filename:join([CaseDir, "meta", "tasks"]))),
  Mail = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "mail"]))),
  Templates = sort_by_created_at(read_template_objects(filename:join([CaseDir, "meta", "templates"]))),
  #{'case' => CaseObj, rounds => Rounds, candidates => Candidates, tasks => Tasks, templates => Templates, mail => Mail}.

refresh_case_state(RootDir, CaseId) ->
  {ok, CaseObj0, CaseDir} = load_case(RootDir, CaseId),
  Tasks = read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  ActiveTaskCount =
    length(
      [
        T
       || T <- Tasks,
          counts_as_live_task(get_in_map(T, [state, status], <<>>))
      ]
    ),
  Phase =
    case ActiveTaskCount > 0 of
      true -> <<"monitoring_active">>;
      false -> <<"post_deliberation_extraction">>
  end,
  CaseObj1 =
    update_object(
      CaseObj0,
      now_ts(),
      fun (Obj) ->
        State0 = maps:get(state, Obj, #{}),
        Obj#{state => State0#{active_task_count => ActiveTaskCount, phase => Phase}}
      end
    ),
  persist_case_object(CaseDir, case_file(CaseDir), CaseObj1).

counts_as_live_task(<<"active">>) -> true;
counts_as_live_task(<<"rectification_required">>) -> true;
counts_as_live_task(_) -> false.

rebuild_indexes(RootDir, CaseId) ->
  {ok, _CaseObj, CaseDir} = load_case(RootDir, CaseId),
  Candidates = read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"])),
  Tasks = read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  Mail = read_objects_in_dir(filename:join([CaseDir, "meta", "mail"])),
  IndexDir = filename:join([CaseDir, "meta", "indexes"]),
  ok = write_json(filename:join([IndexDir, "candidates-by-status.json"]), group_ids_by_status(Candidates)),
  ok = write_json(filename:join([IndexDir, "tasks-by-status.json"]), group_ids_by_status(Tasks)),
  UnreadMail = [id_of(M) || M <- Mail, get_in_map(M, [state, status], <<>>) =:= <<"unread">>],
  ok = write_json(filename:join([IndexDir, "mail-unread.json"]), #{mail_ids => UnreadMail}),
  ok.

group_ids_by_status(Objs) ->
  lists:foldl(
    fun (Obj, Acc0) ->
      Status = get_in_map(Obj, [state, status], <<"unknown">>),
      Id = id_of(Obj),
      Prev = maps:get(Status, Acc0, []),
      Acc0#{Status => Prev ++ [Id]}
    end,
    #{},
    Objs
  ).

mark_candidate_mail_acted(CaseDir, CandidateId, Action, Actor, Now) ->
  MailDir = filename:join([CaseDir, "meta", "mail"]),
  Paths = json_files(MailDir),
  lists:foreach(
    fun (Path) ->
      Mail0 = read_json(Path),
      case mail_targets_candidate(Mail0, CandidateId) of
        true ->
          Mail1 =
            update_object(
              Mail0,
              Now,
              fun (Obj) ->
                Obj#{
                  state =>
                    maps:merge(
                      maps:get(state, Obj, #{}),
                      compact_map(
                        #{status => <<"acted">>, acted_at => Now, acted_action => Action, consumed_by_op_id => Actor}
                      )
                    )
                }
              end
            ),
          ok = persist_case_object(CaseDir, Path, Mail1);
        false -> ok
      end
    end,
    Paths
  ),
  ok.

mail_targets_candidate(MailObj, CandidateId) ->
  Refs = get_in_map(MailObj, [links, related_object_refs], []),
  lists:any(
    fun (Ref0) ->
      Ref = ensure_map(Ref0),
      get_bin(Ref, [type], <<>>) =:= <<"monitoring_candidate">> andalso get_bin(Ref, [id], <<>>) =:= CandidateId
    end,
    ensure_list_of_maps(Refs)
  ).

resolve_round_id(CaseDir, Input, CaseObj) ->
  case get_bin(Input, [round_id, roundId], undefined) of
    undefined -> get_in_map(CaseObj, [links, current_round_id], newest_round_id(CaseDir));
    Value -> Value
  end.

newest_round_id(CaseDir) ->
  Rounds = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  case lists:reverse(Rounds) of
    [Round | _] -> id_of(Round);
    [] -> throw({error, round_not_found})
  end.

ensure_workflow_session_completed(RootDir, WorkflowSessionId0) ->
  WorkflowSessionId = ensure_list(WorkflowSessionId0),
  Events = openagentic_session_store:read_events(RootDir, WorkflowSessionId),
  case latest_workflow_done_event(Events) of
    undefined -> throw({error, workflow_session_not_completed});
    Event ->
      case get_bin(Event, [status], <<>>) of
        <<"completed">> -> ok;
        _ -> throw({error, workflow_session_not_completed})
      end
  end.

latest_workflow_done_event(Events) ->
  lists:foldl(
    fun (Event0, Acc0) ->
      Event = ensure_map(Event0),
      case get_bin(Event, [type], <<>>) of
        <<"workflow.done">> -> Event;
        _ -> Acc0
      end
    end,
    undefined,
    Events
  ).

infer_candidate_specs_from_session(RootDir, WorkflowSessionId0, DefaultTimezone) ->
  WorkflowSessionId = ensure_list(WorkflowSessionId0),
  Events = openagentic_session_store:read_events(RootDir, WorkflowSessionId),
  Text = latest_text_candidate(Events),
  infer_candidate_specs_from_text(Text, DefaultTimezone).

latest_text_candidate(Events) ->
  lists:foldl(
    fun (Event0, Best0) ->
      Event = ensure_map(Event0),
      Type = get_bin(Event, [type], <<>>),
      Candidate =
        case Type of
          <<"workflow.done">> -> get_bin(Event, [final_text], <<>>);
          <<"result">> -> get_bin(Event, [final_text], <<>>);
          <<"assistant.message">> -> get_bin(Event, [text], <<>>);
          _ -> <<>>
        end,
      case byte_size(trim_bin(Candidate)) > 0 of
        true -> Candidate;
        false -> Best0
      end
    end,
    <<>>,
    Events
  ).

infer_candidate_specs_from_text(Text0, DefaultTimezone) ->
  Text = normalize_newlines(to_bin(Text0)),
  Lines0 = binary:split(Text, <<"\n">>, [global]),
  Lines = [trim_bin(Line) || Line <- Lines0, byte_size(trim_bin(Line)) > 0],
  BulletLines0 = [strip_bullet(Line) || Line <- Lines, is_bullet_line(Line)],
  BulletLines =
    case [Line || Line <- BulletLines0, candidate_like_line(Line)] of
      [] -> BulletLines0;
      Filtered -> Filtered
    end,
  [candidate_spec_from_line(Line, DefaultTimezone) || Line <- BulletLines, byte_size(Line) > 0].

candidate_like_line(Line0) ->
  Line = string:lowercase(to_bin(Line0)),
  lists:any(
    fun (Pattern) -> binary:match(Line, Pattern) =/= nomatch end,
    [<<"监测">>, <<"跟踪">>, <<"观察">>, <<"关注">>, <<"monitor">>, <<"track">>, <<"watch">>]
  ).

candidate_spec_from_line(Line0, DefaultTimezone) ->
  Line = trim_bin(Line0),
  #{
    title => shorten_title(Line),
    mission_statement => Line,
    objective => Line,
    default_timezone => DefaultTimezone,
    schedule_policy => default_schedule_policy(DefaultTimezone),
    report_contract => default_report_contract(),
    alert_rules => #{},
    source_strategy => #{},
    tool_profile => #{},
    credential_requirements => #{},
    autonomy_policy => #{mode => <<"review_required">>},
    promotion_policy => #{},
    extracted_summary => Line
  }.
shorten_title(Line) ->
  case byte_size(Line) =< 48 of
    true -> Line;
    false -> binary:part(Line, 0, 48)
  end.

default_schedule_policy(Timezone) ->
  #{mode => <<"manual">>, timezone => Timezone}.

default_report_contract() ->
  #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}.

seed_task_workspace(TaskWorkspaceDir, CandidateObj, Input) ->
  Title = get_bin(Input, [title], get_in_map(CandidateObj, [spec, title], <<"Untitled Task">>)),
  Objective = get_bin(Input, [objective], get_in_map(CandidateObj, [spec, objective], <<>>)),
  Body =
    iolist_to_binary(
      [
        <<"# ">>, Title, <<"\n\n">>,
        <<"## Mission\n">>, get_in_map(CandidateObj, [spec, mission_statement], Objective), <<"\n\n">>,
        <<"## Objective\n">>, Objective, <<"\n">>
      ]
    ),
  file:write_file(filename:join([TaskWorkspaceDir, "TASK.md"]), Body).

seed_template_workspace(TemplateWorkspaceDir, Input, CaseObj) ->
  Title = get_bin(Input, [title], <<"Untitled Template">>),
  Objective = get_bin(Input, [objective], <<>>),
  Summary = get_bin(Input, [summary], <<>>),
  TemplateBody = get_bin(Input, [template_body, templateBody], undefined),
  Body =
    case TemplateBody of
      undefined ->
        iolist_to_binary(
          [
            <<"# ">>, Title, <<"\n\n">>,
            <<"## Summary\n">>, Summary, <<"\n\n">>,
            <<"## Objective\n">>, Objective, <<"\n\n">>,
            <<"## Timezone\n">>, default_timezone(CaseObj), <<"\n">>
          ]
        );
      Value -> Value
    end,
  file:write_file(filename:join([TemplateWorkspaceDir, "TEMPLATE.md"]), Body).

sort_by_created_at(Objs) ->
  lists:sort(
    fun (A, B) ->
      get_in_map(A, [header, created_at], 0) =< get_in_map(B, [header, created_at], 0)
    end,
    Objs
  ).

read_task_objects(TaskRoot) ->
  TaskDirs = safe_list_dir(TaskRoot),
  lists:foldl(
    fun (Name, Acc) ->
      Path = filename:join([TaskRoot, Name, "task.json"]),
      case filelib:is_file(Path) of
        true -> [read_json(Path) | Acc];
        false -> Acc
      end
    end,
    [],
    TaskDirs
  ).

read_template_objects(TemplateRoot) ->
  TemplateDirs = safe_list_dir(TemplateRoot),
  lists:foldl(
    fun (Name, Acc) ->
      Path = filename:join([TemplateRoot, Name, "template.json"]),
      case filelib:is_file(Path) of
        true -> [read_json(Path) | Acc];
        false -> Acc
      end
    end,
    [],
    TemplateDirs
  ).

read_task_versions(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "versions"]))).

read_task_credential_bindings(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "credential_bindings"]))).

read_task_runs(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "runs"]))).

read_task_run_attempts(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "attempts"]))).

read_task_fact_reports(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "reports"]))).

read_task_exception_briefs(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "briefs"]))).

build_task_artifacts(Reports0) ->
  Reports = [ensure_map(Report) || Report <- Reports0],
  lists:foldl(
    fun (Report, Acc0) ->
      ArtifactRefs = get_in_map(Report, [spec, artifact_refs], []),
      Acc0 ++ ensure_list_of_maps(ArtifactRefs)
    end,
    [],
    Reports
  ).

read_objects_in_dir(Dir) ->
  [read_json(Path) || Path <- json_files(Dir)].

json_files(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} ->
      [filename:join([Dir, Name]) || Name <- Names, filename:extension(Name) =:= ".json"];
    _ ->
      []
  end.

safe_list_dir(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} -> Names;
    _ -> []
  end.

load_case(RootDir, CaseId0) ->
  CaseId = to_bin(CaseId0),
  CaseDir = case_dir(RootDir, CaseId),
  Path = case_file(CaseDir),
  case filelib:is_file(Path) of
    true -> {ok, read_json(Path), CaseDir};
    false -> {error, not_found}
  end.

case_dir(RootDir, CaseId0) ->
  CaseId = ensure_list(CaseId0),
  filename:join([RootDir, "cases", CaseId]).

case_file(CaseDir) -> filename:join([CaseDir, "meta", "case.json"]).

round_file(CaseDir, RoundId0) ->
  RoundId = ensure_list(RoundId0),
  filename:join([CaseDir, "meta", "rounds", RoundId ++ ".json"]).

candidate_file(CaseDir, CandidateId0) ->
  CandidateId = ensure_list(CandidateId0),
  filename:join([CaseDir, "meta", "candidates", CandidateId ++ ".json"]).

task_file(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "task.json"]).

task_version_file(CaseDir, TaskId0, VersionId0) ->
  TaskId = ensure_list(TaskId0),
  VersionId = ensure_list(VersionId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "versions", VersionId ++ ".json"]).

credential_binding_file(CaseDir, TaskId0, BindingId0) ->
  TaskId = ensure_list(TaskId0),
  BindingId = ensure_list(BindingId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "credential_bindings", BindingId ++ ".json"]).

run_file(CaseDir, TaskId0, RunId0) ->
  TaskId = ensure_list(TaskId0),
  RunId = ensure_list(RunId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "runs", RunId ++ ".json"]).

run_attempt_file(CaseDir, TaskId0, AttemptId0) ->
  TaskId = ensure_list(TaskId0),
  AttemptId = ensure_list(AttemptId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "attempts", AttemptId ++ ".json"]).

fact_report_file(CaseDir, TaskId0, ReportId0) ->
  TaskId = ensure_list(TaskId0),
  ReportId = ensure_list(ReportId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "reports", ReportId ++ ".json"]).

exception_brief_file(CaseDir, TaskId0, BriefId0) ->
  TaskId = ensure_list(TaskId0),
  BriefId = ensure_list(BriefId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "briefs", BriefId ++ ".json"]).

attempt_scratch_ref(TaskId0, RunId0, AttemptId0) ->
  TaskId = ensure_list(TaskId0),
  RunId = ensure_list(RunId0),
  AttemptId = ensure_list(AttemptId0),
  iolist_to_binary(["runs/", TaskId, "/", RunId, "/attempts/", AttemptId, "/scratch"]).

deliverables_dir(CaseDir, TaskId0, RunId0) ->
  TaskId = ensure_list(TaskId0),
  RunId = ensure_list(RunId0),
  filename:join([CaseDir, "artifacts", "tasks", TaskId, "runs", RunId]).

deliverable_ref(TaskId0, RunId0, FileName0) ->
  TaskId = ensure_list(TaskId0),
  RunId = ensure_list(RunId0),
  FileName = ensure_list(FileName0),
  iolist_to_binary(["artifacts/tasks/", TaskId, "/runs/", RunId, "/", FileName]).

task_history_file(CaseDir, TaskId0) ->
  TaskId = ensure_list(TaskId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "history.jsonl"]).

template_file(CaseDir, TemplateId0) ->
  TemplateId = ensure_list(TemplateId0),
  filename:join([CaseDir, "meta", "templates", TemplateId, "template.json"]).

template_history_file(CaseDir, TemplateId0) ->
  TemplateId = ensure_list(TemplateId0),
  filename:join([CaseDir, "meta", "templates", TemplateId, "history.jsonl"]).

case_history_file(CaseDir) -> filename:join([CaseDir, "meta", "history.jsonl"]).

object_type_registry_file(CaseDir) -> filename:join([CaseDir, "meta", "object-type-registry.json"]).

mail_file(CaseDir, MailId0) ->
  MailId = ensure_list(MailId0),
  filename:join([CaseDir, "meta", "mail", MailId ++ ".json"]).

ensure_case_layout(CaseDir) ->
  ensure_dirs(
    [
      filename:join([CaseDir, "meta", "rounds"]),
      filename:join([CaseDir, "meta", "candidates"]),
      filename:join([CaseDir, "meta", "tasks"]),
      filename:join([CaseDir, "meta", "templates"]),
      filename:join([CaseDir, "meta", "mail"]),
      filename:join([CaseDir, "meta", "indexes"]),
      filename:join([CaseDir, "artifacts"]),
      filename:join([CaseDir, "workspaces"]),
      filename:join([CaseDir, "workspaces", "templates"]),
      filename:join([CaseDir, "published"])
    ]
  ).

ensure_dirs([]) -> ok;
ensure_dirs([Dir | Rest]) ->
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  ensure_dirs(Rest).

write_json(Path, Obj0) ->
  Obj = ensure_map(Obj0),
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  Tmp = Path ++ ".tmp." ++ ensure_list(new_id(<<"tmp">>)),
  Body = openagentic_json:encode_safe(Obj),
  ok = file:write_file(Tmp, <<Body/binary, "\n">>),
  case file:rename(Tmp, Path) of
    ok -> ok;
    _ ->
      _ = file:delete(Path),
      ok = file:rename(Tmp, Path),
      ok
  end.

persist_case_object(CaseDir, Path, Obj0) ->
  Obj = ensure_map(Obj0),
  ok = write_json(Path, Obj),
  case get_bin(Obj, [header, type], undefined) of
    undefined -> ok;
    <<>> -> ok;
    _ ->
      ok = touch_object_type_registry(CaseDir, Obj, Path),
      ok = append_history_line(case_history_file(CaseDir), build_history_entry(Obj, Path)),
      case object_history_path(CaseDir, Obj) of
        undefined -> ok;
        ObjectHistoryPath -> append_history_line(ObjectHistoryPath, build_history_entry(Obj, Path))
      end
  end.

touch_object_type_registry(CaseDir, Obj, Path) ->
  RegistryPath = object_type_registry_file(CaseDir),
  Registry0 =
    case filelib:is_file(RegistryPath) of
      true -> read_json(RegistryPath);
      false -> #{}
    end,
  Objects0 = ensure_map(maps:get(objects, Registry0, #{})),
  ObjectId = id_of(Obj),
  Type = get_in_map(Obj, [header, type], <<"unknown">>),
  Entry =
    compact_map(
      #{
        type => Type,
        revision => get_in_map(Obj, [header, revision], undefined),
        updated_at => get_in_map(Obj, [header, updated_at], undefined),
        path => to_bin(Path)
      }
    ),
  Objects1 = Objects0#{ObjectId => Entry},
  TypeCounts =
    maps:fold(
      fun (_Id, Meta0, Acc0) ->
        Meta = ensure_map(Meta0),
        MetaType = get_bin(Meta, [type], <<"unknown">>),
        Acc0#{MetaType => maps:get(MetaType, Acc0, 0) + 1}
      end,
      #{},
      Objects1
    ),
  Registry1 =
    maps:merge(
      Registry0,
      #{
        schema_version => <<"case-governance-object-registry/v1">>,
        updated_at => now_ts(),
        objects => Objects1,
        type_counts => TypeCounts
      }
    ),
  write_json(RegistryPath, Registry1).

build_history_entry(Obj, Path) ->
  compact_map(
    #{
      at => get_in_map(Obj, [header, updated_at], undefined),
      object_id => id_of(Obj),
      object_type => get_in_map(Obj, [header, type], undefined),
      revision => get_in_map(Obj, [header, revision], undefined),
      status => get_in_map(Obj, [state, status], undefined),
      path => to_bin(Path)
    }
  ).

object_history_path(CaseDir, Obj) ->
  case get_in_map(Obj, [header, type], <<>>) of
    <<"monitoring_task">> -> task_history_file(CaseDir, id_of(Obj));
    <<"task_version">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"credential_binding">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"monitoring_run">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"run_attempt">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"fact_report">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"briefing">> -> task_history_file(CaseDir, get_in_map(Obj, [links, task_id], undefined));
    <<"task_template">> -> template_history_file(CaseDir, id_of(Obj));
    _ -> undefined
  end.

append_history_line(Path, Entry0) ->
  Entry = ensure_map(Entry0),
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  Body = openagentic_json:encode_safe(Entry),
  file:write_file(Path, <<Body/binary, "\n">>, [append]).

read_json(Path) ->
  {ok, Bin} = file:read_file(Path),
  decode_json(Bin).

decode_json(Bin) ->
  normalize_keys(openagentic_json:decode(trim_bin(Bin))).

normalize_keys(Map) when is_map(Map) ->
  maps:from_list([{normalize_key(K), normalize_keys(V)} || {K, V} <- maps:to_list(Map)]);
normalize_keys(List) when is_list(List) ->
  [normalize_keys(Item) || Item <- List];
normalize_keys(Other) -> Other.

normalize_key(K) when is_binary(K) -> binary_to_atom(K, utf8);
normalize_key(K) -> K.

update_object(Obj0, Now, Fun) ->
  Obj1 = ensure_map(Fun(Obj0)),
  Header0 = maps:get(header, Obj1, #{}),
  Revision0 = get_int(Header0, [revision], 0),
  Obj1#{header => Header0#{updated_at => Now, revision => Revision0 + 1}}.

header(Id, Type, Now) ->
  #{id => Id, type => Type, schema_version => <<"case-governance/v1">>, created_at => Now, updated_at => Now, revision => 1}.

display_code(Prefix) ->
  Suffix = integer_to_binary(erlang:unique_integer([positive, monotonic])),
  <<Prefix/binary, $-, Suffix/binary>>.

new_id(Prefix) ->
  Ts = integer_to_binary(erlang:system_time(microsecond)),
  N = integer_to_binary(erlang:unique_integer([positive, monotonic])),
  <<Prefix/binary, $_, Ts/binary, $_, N/binary>>.

id_of(Obj) -> get_in_map(Obj, [header, id], <<>>).

default_timezone(CaseObj) -> get_in_map(CaseObj, [spec, default_timezone], <<"Asia/Shanghai">>).

compact_map(Map) -> maps:filter(fun (_K, V) -> V =/= undefined end, ensure_map(Map)).

initial_task_status(CredentialRequirements) ->
  case required_credential_slots(CredentialRequirements) of
    [] -> <<"active">>;
    _ -> <<"awaiting_credentials">>
  end.

task_health_for_status(<<"active">>) -> <<"ok">>;
task_health_for_status(<<"ready_to_activate">>) -> <<"pending_activation">>;
task_health_for_status(<<"awaiting_credentials">>) -> <<"authorization_pending">>;
task_health_for_status(<<"credential_expired">>) -> <<"credential_expired">>;
task_health_for_status(<<"reauthorization_required">>) -> <<"reauthorization_required">>;
task_health_for_status(_) -> <<"ok">>.

build_credential_binding(CaseId, TaskId, BindingId, Input, SlotName, Now) ->
  #{
    header => header(BindingId, <<"credential_binding">>, Now),
    links => compact_map(#{case_id => CaseId, task_id => TaskId}),
    spec =>
      compact_map(
        #{
          slot_name => SlotName,
          binding_type => get_bin(Input, [binding_type, bindingType], undefined),
          provider => get_bin(Input, [provider], undefined),
          material_ref => get_bin(Input, [material_ref, materialRef], undefined)
        }
      ),
    state =>
      compact_map(
        #{
          status => get_bin(Input, [status], <<"validated">>),
          validated_at => resolve_validated_at(Input, Now),
          expires_at => get_number(Input, [expires_at, expiresAt], undefined)
        }
      ),
    audit =>
      compact_map(
        #{
          created_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
          note => get_bin(Input, [note], undefined)
        }
      ),
    ext => #{}
  }.

update_credential_binding(Binding0, Input, SlotName, Now) ->
  update_object(
    Binding0,
    Now,
    fun (Obj) ->
      Obj#{
        spec =>
          maps:merge(
            maps:get(spec, Obj, #{}),
            compact_map(
              #{
                slot_name => SlotName,
                binding_type => get_bin(Input, [binding_type, bindingType], get_in_map(Obj, [spec, binding_type], undefined)),
                provider => get_bin(Input, [provider], get_in_map(Obj, [spec, provider], undefined)),
                material_ref => get_bin(Input, [material_ref, materialRef], get_in_map(Obj, [spec, material_ref], undefined))
              }
            )
          ),
        state =>
          maps:merge(
            maps:get(state, Obj, #{}),
            compact_map(
              #{
                status => get_bin(Input, [status], get_in_map(Obj, [state, status], <<"validated">>)),
                validated_at => resolve_validated_at(Input, Now, Obj),
                expires_at => get_number(Input, [expires_at, expiresAt], get_in_map(Obj, [state, expires_at], undefined))
              }
            )
          ),
        audit =>
          maps:merge(
            maps:get(audit, Obj, #{}),
            compact_map(
              #{
                updated_by_op_id => get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                note => get_bin(Input, [note], undefined)
              }
            )
          )
      }
    end
  ).

resolve_credential_binding_id(Input, ExistingBindings) ->
  case get_bin(Input, [credential_binding_id, credentialBindingId], undefined) of
    undefined ->
      SlotName = get_bin(Input, [slot_name, slotName], <<>>),
      Provider = get_bin(Input, [provider], <<>>),
      BindingType = get_bin(Input, [binding_type, bindingType], <<>>),
      case lists:filter(
             fun (Binding) ->
               get_in_map(Binding, [spec, slot_name], <<>>) =:= SlotName andalso
                 get_in_map(Binding, [spec, provider], <<>>) =:= Provider andalso
                 get_in_map(Binding, [spec, binding_type], <<>>) =:= BindingType
             end,
             ExistingBindings
           ) of
        [Binding | _] -> id_of(Binding);
        [] -> new_id(<<"binding">>)
      end;
    BindingId -> BindingId
  end.

resolve_validated_at(Input, Now) ->
  resolve_validated_at(Input, Now, #{}).

resolve_validated_at(Input, Now, Existing) ->
  case get_number(Input, [validated_at, validatedAt], undefined) of
    undefined ->
      case get_bin(Input, [status], get_in_map(Existing, [state, status], <<"validated">>)) of
        <<"validated">> ->
          case get_in_map(Existing, [state, validated_at], undefined) of
            undefined -> Now;
            Value -> Value
          end;
        _ -> get_in_map(Existing, [state, validated_at], undefined)
      end;
    Value -> Value
  end.

sync_task_authorization(CaseDir, Task0, Now) ->
  TaskId = get_in_map(Task0, [header, id], <<>>),
  Versions = read_task_versions(CaseDir, TaskId),
  CredentialBindings = read_task_credential_bindings(CaseDir, TaskId),
  Authorization0 = build_task_authorization(Task0, Versions, CredentialBindings),
  Status0 = get_in_map(Task0, [state, status], <<"active">>),
  NextStatus =
    case maps:get(status, Authorization0, <<"active">>) of
      <<"ready_to_activate">> when Status0 =:= <<"active">> -> <<"active">>;
      Value -> Value
    end,
  NextRefs = [id_of(Binding) || Binding <- CredentialBindings],
  Task1 =
    update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{
          spec => maps:merge(maps:get(spec, Obj, #{}), #{credential_binding_refs => NextRefs}),
          state => maps:merge(maps:get(state, Obj, #{}), #{status => NextStatus, health => task_health_for_status(NextStatus)})
        }
      end
    ),
  ok = persist_case_object(CaseDir, task_file(CaseDir, TaskId), Task1),
  {Task1, Authorization0#{status => NextStatus}}.

build_task_authorization(Task, Versions, CredentialBindings) ->
  RequiredSlots = required_credential_slots_from_versions(Versions),
  ValidSlots =
    unique_binaries(
      [get_in_map(Binding, [spec, slot_name], <<>>) || Binding <- CredentialBindings, binding_status_valid(Binding)]
    ),
  ExpiredSlots =
    unique_binaries(
      [get_in_map(Binding, [spec, slot_name], <<>>) || Binding <- CredentialBindings, binding_status_expired(Binding)]
    ),
  MissingSlots = [Slot || Slot <- RequiredSlots, not lists:member(Slot, ValidSlots)],
  CurrentStatus = get_in_map(Task, [state, status], <<"active">>),
  WasActivated =
    get_in_map(Task, [state, activated_at], undefined) =/= undefined orelse
      get_in_map(Task, [audit, activated_at], undefined) =/= undefined,
  Status =
    case RequiredSlots of
      [] -> <<"active">>;
      _ when ExpiredSlots =/= [] -> <<"credential_expired">>;
      _ when MissingSlots =/= [], WasActivated -> <<"reauthorization_required">>;
      _ when MissingSlots =/= [] -> <<"awaiting_credentials">>;
      _ when CurrentStatus =:= <<"active">> -> <<"active">>;
      _ -> <<"ready_to_activate">>
    end,
  #{required_slots => RequiredSlots, valid_slots => ValidSlots, missing_slots => MissingSlots, expired_slots => ExpiredSlots, status => Status}.

build_latest_version_diff(Versions0, Authorization0) ->
  Versions = [ensure_map(V) || V <- Versions0],
  Authorization = ensure_map(Authorization0),
  case lists:reverse(Versions) of
    [Current0, Previous0 | _] ->
      Current = ensure_map(Current0),
      Previous = ensure_map(Previous0),
      CurrentSpec = ensure_map(maps:get(spec, Current, #{})),
      PreviousSpec = ensure_map(maps:get(spec, Previous, #{})),
      BeforeSlots = required_credential_slots(get_in_map(PreviousSpec, [credential_requirements], #{})),
      AfterSlots = required_credential_slots(get_in_map(CurrentSpec, [credential_requirements], #{})),
      NewlyRequired = [Slot || Slot <- AfterSlots, not lists:member(Slot, BeforeSlots)],
      RemovedSlots = [Slot || Slot <- BeforeSlots, not lists:member(Slot, AfterSlots)],
      ChangedFields = version_changed_fields(PreviousSpec, CurrentSpec),
      CredentialRequirementsChanged = BeforeSlots =/= AfterSlots,
      ReauthorizationRequired =
        CredentialRequirementsChanged andalso maps:get(status, Authorization, <<"active">>) =/= <<"active">>,
      #{
        from_version_id => id_of(Previous),
        to_version_id => id_of(Current),
        change_summary => get_in_map(Current, [audit, change_summary], <<>>),
        changed_fields => ChangedFields,
        changed_field_count => length(ChangedFields),
        credential_requirements_changed => CredentialRequirementsChanged,
        newly_required_slots => NewlyRequired,
        removed_required_slots => RemovedSlots,
        reauthorization_required => ReauthorizationRequired,
        authorization_status => maps:get(status, Authorization, <<"active">>)
      };
    _ ->
      #{}
  end.

first_defined([]) -> undefined;
first_defined([undefined | Rest]) -> first_defined(Rest);
first_defined([Value | _]) -> Value.

task_run_in_progress_error(CaseDir, TaskId0) ->
  TaskId = to_bin(TaskId0),
  case lists:reverse(read_task_runs(CaseDir, TaskId)) of
    [Run | _] ->
      case get_in_map(Run, [state, status], <<>>) of
        <<"running">> -> run_in_progress;
        <<"scheduled">> -> run_in_progress;
        _ -> undefined
      end;
    [] ->
      undefined
  end.

task_workspace_dir(CaseDir, Task0) ->
  Task = ensure_map(Task0),
  case get_in_map(Task, [links, workspace_ref], undefined) of
    undefined -> CaseDir;
    Ref -> filename:join([CaseDir, ensure_list(Ref)])
  end.

build_monitoring_run_context(CaseDir, Task0, Version0) ->
  Task = ensure_map(Task0),
  Version = ensure_map(Version0),
  TaskId = id_of(Task),
  Versions = read_task_versions(CaseDir, TaskId),
  Runs = lists:reverse(read_task_runs(CaseDir, TaskId)),
  Attempts = lists:reverse(read_task_run_attempts(CaseDir, TaskId)),
  Reports = lists:reverse(read_task_fact_reports(CaseDir, TaskId)),
  Briefs = lists:reverse(read_task_exception_briefs(CaseDir, TaskId)),
  #{
    task_workspace_ref => get_in_map(Task, [links, workspace_ref], undefined),
    current_task_version_id => id_of(Version),
    historical_version_summary => build_historical_version_summary(Versions),
    historical_execution_summary => build_historical_execution_summary(Runs, Attempts, Reports),
    latest_report_summary => build_latest_report_summary(Reports),
    latest_exception_summary => build_latest_exception_summary(Attempts, Briefs),
    recent_rectification_summary => build_recent_rectification_summary(Versions)
  }.

build_historical_version_summary(Versions0) ->
  Versions = lists:reverse([ensure_map(Version) || Version <- Versions0]),
  lists:sublist(
    [
      compact_map(
        #{
          task_version_id => id_of(Version),
          status => get_in_map(Version, [state, status], undefined),
          created_at => get_in_map(Version, [header, created_at], undefined),
          change_summary => get_in_map(Version, [audit, change_summary], undefined),
          revised_by_op_id => get_in_map(Version, [audit, revised_by_op_id], undefined),
          objective => get_in_map(Version, [spec, objective], undefined)
        }
      )
     || Version <- Versions
    ],
    5
  ).

build_historical_execution_summary(Runs0, Attempts0, Reports0) ->
  Runs = [ensure_map(Run) || Run <- Runs0],
  Attempts = [ensure_map(Attempt) || Attempt <- Attempts0],
  Reports = [ensure_map(Report) || Report <- Reports0],
  lists:sublist(
    [
      compact_map(
        #{
          run_id => id_of(Run),
          status => get_in_map(Run, [state, status], undefined),
          planned_for_at => get_in_map(Run, [spec, planned_for_at], undefined),
          attempt_count => get_in_map(Run, [state, attempt_count], undefined),
          last_attempt_status => get_in_map(Run, [state, last_attempt_status], undefined),
          result_summary => get_in_map(Run, [state, result_summary], undefined),
          latest_attempt => summarize_attempt(find_attempt(Attempts, get_in_map(Run, [links, latest_attempt_id], undefined))),
          fact_report => summarize_report(find_report(Reports, get_in_map(Run, [links, report_id], undefined)))
        }
      )
     || Run <- Runs
    ],
    5
  ).

summarize_attempt(undefined) -> #{};
summarize_attempt(Attempt0) ->
  Attempt = ensure_map(Attempt0),
  compact_map(
    #{
      attempt_id => id_of(Attempt),
      status => get_in_map(Attempt, [state, status], undefined),
      failure_class => get_in_map(Attempt, [state, failure_class], undefined),
      failure_summary => get_in_map(Attempt, [state, failure_summary], undefined),
      execution_session_id => get_in_map(Attempt, [links, execution_session_id], undefined),
      scratch_ref => get_in_map(Attempt, [links, scratch_ref], undefined)
    }
  ).

summarize_report(undefined) -> #{};
summarize_report(Report0) ->
  Report = ensure_map(Report0),
  compact_map(
    #{
      report_id => id_of(Report),
      status => get_in_map(Report, [state, status], undefined),
      quality_summary => get_in_map(Report, [state, quality_summary], undefined),
      alert_summary => get_in_map(Report, [state, alert_summary], undefined),
      report_lineage_id => get_in_map(Report, [ext, report_lineage_id], undefined),
      supersedes_report_id => get_in_map(Report, [ext, supersedes_report_id], undefined)
    }
  ).

find_report([], _ReportId) -> undefined;
find_report([Report | Rest], ReportId) ->
  case id_of(Report) =:= ReportId of
    true -> Report;
    false -> find_report(Rest, ReportId)
  end.

build_latest_exception_summary(Attempts0, Briefs0) ->
  Attempts = lists:reverse([ensure_map(Attempt) || Attempt <- Attempts0]),
  Briefs = lists:reverse([ensure_map(Brief) || Brief <- Briefs0]),
  case [Attempt || Attempt <- Attempts, get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>] of
    [Attempt | _] ->
      AttemptId = id_of(Attempt),
      Brief =
        case [Item || Item <- Briefs, get_in_map(Item, [links, attempt_id], undefined) =:= AttemptId] of
          [Item | _] -> Item;
          [] -> undefined
        end,
      compact_map(
        #{
          attempt_id => AttemptId,
          failure_class => get_in_map(Attempt, [state, failure_class], undefined),
          failure_summary => get_in_map(Attempt, [state, failure_summary], undefined),
          execution_session_id => get_in_map(Attempt, [links, execution_session_id], undefined),
          exception_brief_id =>
            case Brief of
              undefined -> undefined;
              _ -> id_of(Brief)
            end
        }
      );
    [] ->
      #{}
  end.

build_latest_report_summary(Reports0) ->
  Reports = lists:reverse([ensure_map(Report) || Report <- Reports0]),
  case Reports of
    [Report | _] -> summarize_report(Report);
    [] -> #{}
  end.

build_recent_rectification_summary(Versions0) ->
  Versions = lists:reverse([ensure_map(Version) || Version <- Versions0]),
  case Versions of
    [Current, Previous | _] ->
      compact_map(
        #{
          current_version_id => id_of(Current),
          previous_version_id => id_of(Previous),
          change_summary => get_in_map(Current, [audit, change_summary], undefined),
          revised_by_op_id => get_in_map(Current, [audit, revised_by_op_id], undefined)
        }
      );
    _ -> #{}
  end.

build_task_failure_stats(Runs0, Attempts0) ->
  Attempts = [ensure_map(Attempt) || Attempt <- Attempts0],
  FailedAttempts = [Attempt || Attempt <- Attempts, get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>],
  #{
    total_failed_attempts => length(FailedAttempts),
    consecutive_failure_count => consecutive_failure_count(Runs0, Attempts0),
    latest_failure_class => latest_failure_class(Attempts0),
    by_class => count_failures_by_class(FailedAttempts)
  }.

count_failures_by_class(Attempts0) ->
  lists:foldl(
    fun (Attempt0, Acc0) ->
      Attempt = ensure_map(Attempt0),
      FailureClass = get_in_map(Attempt, [state, failure_class], <<"unknown">>),
      Prev = maps:get(FailureClass, Acc0, 0),
      Acc0#{FailureClass => Prev + 1}
    end,
    #{},
    Attempts0
  ).

validate_report_contract(Version0, Delivery0) ->
  Version = ensure_map(Version0),
  Delivery = ensure_map(Delivery0),
  ReportContract = ensure_map(get_in_map(Version, [spec, report_contract], #{})),
  Markdown = get_bin(Delivery, [report_markdown], <<>>),
  Facts = ensure_list_of_maps(get_in_map(Delivery, [facts], [])),
  Artifacts = ensure_list_of_maps(get_in_map(Delivery, [artifacts], [])),
  RequiredSections = [to_bin(Item) || Item <- get_list(ReportContract, [required_sections, requiredSections], [])],
  MissingSections = missing_markdown_sections(Markdown, RequiredSections),
  RequiredFactFields = [to_bin(Item) || Item <- get_list(ReportContract, [required_fact_fields, requiredFactFields], [])],
  MissingFactFields = missing_required_fact_fields(Facts, RequiredFactFields),
  case {Artifacts =:= [], MissingSections, MissingFactFields} of
    {true, _, _} ->
      {error, <<"report_contract_rejected">>, <<"artifacts.json must contain at least one formal artifact reference">>};
    {false, [_ | _], _} ->
      {error, <<"report_contract_rejected">>, format_missing_sections(MissingSections)};
    {false, [], [_ | _]} ->
      {error, <<"report_contract_rejected">>, format_missing_fact_fields(MissingFactFields)};
    _ ->
      ok
  end.

missing_markdown_sections(_Markdown, []) -> [];
missing_markdown_sections(Markdown0, Sections0) ->
  Markdown = string:lowercase(to_bin(Markdown0)),
  [Section || Section <- Sections0, not markdown_has_section(Markdown, string:lowercase(to_bin(Section)))].

markdown_has_section(Markdown, Section) ->
  Patterns = [<<"## ", Section/binary>>, <<"# ", Section/binary>>, <<"### ", Section/binary>>],
  lists:any(fun (Pattern) -> binary:match(Markdown, Pattern) =/= nomatch end, Patterns).

missing_required_fact_fields(_Facts, []) -> [];
missing_required_fact_fields(Facts, Fields) ->
  Missing =
    [
      Field
     || Field <- Fields,
        lists:any(fun (Fact) -> fact_field_missing(ensure_map(Fact), Field) end, Facts)
    ],
  unique_binaries(Missing).

fact_field_missing(Fact, Field) ->
  trim_bin(fact_field_value(Fact, Field)) =:= <<>>.

fact_field_value(Fact, Field) ->
  case maps:get(Field, Fact, undefined) of
    undefined ->
      case field_atom(Field) of
        undefined -> <<>>;
        Atom -> to_bin(maps:get(Atom, Fact, <<>>))
      end;
    Value ->
      to_bin(Value)
  end.

field_atom(Bin) when is_binary(Bin) ->
  try binary_to_existing_atom(Bin, utf8) of
    Atom -> Atom
  catch
    _:_ -> undefined
  end;
field_atom(Atom) when is_atom(Atom) -> Atom;
field_atom(_) -> undefined.

format_missing_sections(Sections) ->
  iolist_to_binary([<<"report_contract missing markdown sections: ">>, binary:join([to_bin(Section) || Section <- Sections], <<", ">>)]).

format_missing_fact_fields(Fields) ->
  iolist_to_binary([<<"report_contract missing required fact fields: ">>, binary:join([to_bin(Field) || Field <- Fields], <<", ">>)]).

classify_runtime_failure({http_error, Status, _Headers, Body}) when Status =:= 401; Status =:= 403 ->
  {<<"auth_expired">>, runtime_failure_summary(Body, {http_error, Status})};
classify_runtime_failure({http_error, Status, _Headers, Body}) when Status =:= 404; Status =:= 408 ->
  {<<"source_unreachable">>, runtime_failure_summary(Body, {http_error, Status})};
classify_runtime_failure({http_error, Status, _Headers, Body}) when Status =:= 409 ->
  {<<"data_conflict_unresolved">>, runtime_failure_summary(Body, {http_error, Status})};
classify_runtime_failure({http_error, Status, _Headers, Body}) when Status =:= 429 ->
  {<<"rate_limited">>, runtime_failure_summary(Body, {http_error, Status})};
classify_runtime_failure({http_error, Status, _Headers, Body}) when Status >= 500 ->
  {<<"source_unreachable">>, runtime_failure_summary(Body, {http_error, Status})};
classify_runtime_failure(Reason0) ->
  Summary = runtime_failure_summary(undefined, Reason0),
  Lower = string:lowercase(Summary),
  Class =
    case contains_any_fragment(Lower, [<<"expired">>, <<"login required">>, <<"unauthorized">>, <<"401">>, <<"403">>, <<"token expired">>]) of
      true -> <<"auth_expired">>;
      false ->
        case contains_any_fragment(Lower, [<<"rate limit">>, <<"rate_limit">>, <<"429">>, <<"too many requests">>]) of
          true -> <<"rate_limited">>;
          false ->
            case contains_any_fragment(Lower, [<<"schema">>, <<"unexpected field">>, <<"invalid structure">>, <<"parse">>, <<"selector">>]) of
              true -> <<"source_schema_changed">>;
              false ->
                case contains_any_fragment(Lower, [<<"conflict">>, <<"mismatch">>, <<"inconsistent">>]) of
                  true -> <<"data_conflict_unresolved">>;
                  false ->
                    case contains_any_fragment(Lower, [<<"timeout">>, <<"unreachable">>, <<"connection">>, <<"refused">>, <<"dns">>, <<"not found">>, <<"404">>, <<"5xx">>]) of
                      true -> <<"source_unreachable">>;
                      false -> <<"script_runtime_error">>
                    end
                end
            end
        end
    end,
  {Class, Summary}.

runtime_failure_summary(Body, Reason) ->
  Candidate =
    case trim_bin(to_bin(Body)) of
      <<>> -> trim_bin(to_bin(Reason));
      Bin -> Bin
    end,
  case Candidate of
    <<>> -> <<"runtime error">>;
    _ -> Candidate
  end.

contains_any_fragment(Bin, Fragments) ->
  lists:any(fun (Fragment) -> binary:match(Bin, Fragment) =/= nomatch end, Fragments).

delivery_needs_followup(Delivery0) ->
  Delivery = ensure_map(Delivery0),
  Facts = ensure_list_of_maps(get_in_map(Delivery, [facts], [])),
  lists:any(
    fun (Fact0) ->
      Fact = ensure_map(Fact0),
      case string:lowercase(get_bin(Fact, [alert_level, alertLevel], <<"normal">>)) of
        <<"normal">> -> false;
        <<"low">> -> false;
        _ -> true
      end
    end,
    Facts
  ).

build_exception_brief(CaseId, Task0, Run0, Attempt0, FailureClass, FailureSummary, Now) ->
  Task = ensure_map(Task0),
  Run = ensure_map(Run0),
  Attempt = ensure_map(Attempt0),
  BriefId = new_id(<<"brief">>),
  #{
    header => header(BriefId, <<"briefing">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          task_id => id_of(Task),
          run_id => id_of(Run),
          attempt_id => id_of(Attempt),
          execution_session_id => get_in_map(Attempt, [links, execution_session_id], undefined)
        }
      ),
    spec =>
      compact_map(
        #{
          briefing_kind => <<"task_exception_brief">>,
          title => <<"task execution failed">>,
          summary => get_in_map(Task, [spec, title], <<"Untitled Task">>),
          failure_class => FailureClass,
          failure_summary => FailureSummary,
          recommended_action => <<"review_and_rectify">>,
          scratch_ref => get_in_map(Attempt, [links, scratch_ref], undefined)
        }
      ),
    state => #{status => <<"submitted">>, severity => exception_severity(FailureClass), submitted_at => Now},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

build_task_run_failure_mail(CaseId, Task0, Run0, Attempt0, ExceptionBrief0, FailureClass, FailureSummary, Now) ->
  Task = ensure_map(Task0),
  Run = ensure_map(Run0),
  Attempt = ensure_map(Attempt0),
  ExceptionBrief = ensure_map(ExceptionBrief0),
  MailId = new_id(<<"mail">>),
  #{
    header => header(MailId, <<"internal_mail">>, Now),
    links =>
      compact_map(
        #{
          case_id => CaseId,
          related_object_refs =>
            [
              #{type => <<"monitoring_task">>, id => id_of(Task)},
              #{type => <<"monitoring_run">>, id => id_of(Run)},
              #{type => <<"run_attempt">>, id => id_of(Attempt)},
              #{type => <<"briefing">>, id => id_of(ExceptionBrief)}
            ],
          source_op_id => undefined,
          source_session_id => get_in_map(Attempt, [links, execution_session_id], undefined)
        }
      ),
    spec =>
      compact_map(
        #{
          message_type => <<"task_run_failed">>,
          title => <<"task run failed">>,
          summary => get_in_map(Task, [spec, title], <<"Untitled Task">>),
          recommended_action => <<"review">>,
          available_actions => [<<"review">>, <<"rectify_task">>],
          failure_class => FailureClass,
          failure_summary => FailureSummary,
          exception_brief_id => id_of(ExceptionBrief)
        }
      ),
    state => #{status => <<"unread">>, severity => exception_severity(FailureClass), acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

exception_severity(<<"auth_expired">>) -> <<"high">>;
exception_severity(<<"rate_limited">>) -> <<"medium">>;
exception_severity(<<"source_unreachable">>) -> <<"medium">>;
exception_severity(<<"source_schema_changed">>) -> <<"high">>;
exception_severity(<<"data_conflict_unresolved">>) -> <<"high">>;
exception_severity(_) -> <<"medium">>.

version_changed_fields(PreviousSpec, CurrentSpec) ->
  Fields =
    [
      objective,
      schedule_policy,
      report_contract,
      alert_rules,
      source_strategy,
      tool_profile,
      credential_requirements,
      autonomy_policy,
      promotion_policy
    ],
  lists:foldl(
    fun (Field, Acc) ->
      Prev = maps:get(Field, PreviousSpec, undefined),
      Curr = maps:get(Field, CurrentSpec, undefined),
      case Prev =:= Curr of
        true -> Acc;
        false ->
          [
            compact_map(
              #{
                field => atom_to_binary(Field, utf8),
                from => Prev,
                to => Curr
              }
            )
            | Acc
          ]
      end
    end,
    [],
    Fields
  ).

required_credential_slots_from_versions(Versions) ->
  case lists:reverse(Versions) of
    [Version | _] -> required_credential_slots(get_in_map(Version, [spec, credential_requirements], #{}));
    [] -> []
  end.

required_credential_slots(Requirements0) ->
  Requirements = ensure_map(Requirements0),
  case get_bin(Requirements, [slot_name, slotName], undefined) of
    undefined ->
      RawSlots =
        case find_any(Requirements, [required_slots, requiredSlots, slots]) of
          undefined -> [];
          Value when is_list(Value) -> Value;
          Value -> [Value]
        end,
      unique_binaries([slot_name_from_requirement(Item) || Item <- RawSlots, slot_name_from_requirement(Item) =/= <<>>]);
    SlotName -> [SlotName]
  end.

slot_name_from_requirement(Item) when is_binary(Item) -> trim_bin(Item);
slot_name_from_requirement(Item) when is_list(Item) -> trim_bin(to_bin(Item));
slot_name_from_requirement(Item0) ->
  Item = ensure_map(Item0),
  get_bin(Item, [slot_name, slotName, name], <<>>).

binding_status_valid(Binding) ->
  lists:member(get_in_map(Binding, [state, status], <<>>), [<<"validated">>, <<"active">>, <<"ready">>, <<"bound">>]).

binding_status_expired(Binding) ->
  get_in_map(Binding, [state, status], <<>>) =:= <<"expired">>.

activation_error(Authorization) ->
  case maps:get(status, Authorization, <<"active">>) of
    <<"awaiting_credentials">> -> awaiting_credentials;
    <<"credential_expired">> -> credential_expired;
    <<"reauthorization_required">> -> reauthorization_required;
    _ -> undefined
  end.

maybe_check_expected_revision(Input0, Obj0) ->
  Input = ensure_map(Input0),
  Obj = ensure_map(Obj0),
  case find_any(Input, [expected_revision, expectedRevision]) of
    undefined -> ok;
    _ ->
      ExpectedRevision = get_int(Input, [expected_revision, expectedRevision], undefined),
      CurrentRevision = get_in_map(Obj, [header, revision], 0),
      case ExpectedRevision =:= CurrentRevision of
        true -> ok;
        false -> {error, {revision_conflict, CurrentRevision}}
      end
  end.

resolve_binding_context(Input0, ExistingBindings0, RotateBindingId, ExistingBindingId) ->
  Input = ensure_map(Input0),
  ExistingBindings = [ensure_map(Item) || Item <- ExistingBindings0],
  ContextBinding =
    case RotateBindingId of
      undefined -> find_binding_by_id(ExistingBindings, ExistingBindingId);
      _ -> find_binding_by_id(ExistingBindings, RotateBindingId)
    end,
  case ((RotateBindingId =/= undefined) orelse (ExistingBindingId =/= undefined)) andalso ContextBinding =:= undefined of
    true -> {error, not_found};
    false ->
      SlotName =
        case get_bin(Input, [slot_name, slotName], undefined) of
          undefined -> get_in_map(ContextBinding, [spec, slot_name], undefined);
          Value -> Value
        end,
      case SlotName of
        undefined -> {error, {missing_required_field, slot_name}};
        <<>> -> {error, {missing_required_field, slot_name}};
        _ -> {ok, SlotName, binding_defaults_from_existing(ContextBinding), ContextBinding}
      end
  end.

find_binding_by_id(_Bindings, undefined) -> undefined;
find_binding_by_id([], _BindingId) -> undefined;
find_binding_by_id([Binding | Rest], BindingId) ->
  case id_of(Binding) =:= BindingId of
    true -> Binding;
    false -> find_binding_by_id(Rest, BindingId)
  end.

binding_defaults_from_existing(undefined) -> #{};
binding_defaults_from_existing(Binding0) ->
  Binding = ensure_map(Binding0),
  compact_map(
    #{
      slot_name => get_in_map(Binding, [spec, slot_name], undefined),
      binding_type => get_in_map(Binding, [spec, binding_type], undefined),
      provider => get_in_map(Binding, [spec, provider], undefined),
      material_ref => get_in_map(Binding, [spec, material_ref], undefined)
    }
  ).

unique_binaries(List0) ->
  lists:usort([Item || Item <- List0, is_binary(Item), Item =/= <<>>]).

normalize_candidate_specs([]) -> [];
normalize_candidate_specs(Items) when is_list(Items) -> [ensure_map(Item) || Item <- Items];
normalize_candidate_specs(_) -> [].

choose_map(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> ensure_map(Default);
    Value -> ensure_map(Value)
  end.

get_in_map(Map0, [Key], Default) ->
  case find_any(ensure_map(Map0), [Key]) of
    undefined -> Default;
    Value -> Value
  end;
get_in_map(Map0, [Key | Rest], Default) ->
  Map = ensure_map(Map0),
  case find_any(Map, [Key]) of
    undefined -> Default;
    Value -> get_in_map(Value, Rest, Default)
  end.

required_bin(Map, Keys) ->
  case get_bin(Map, Keys, undefined) of
    undefined -> erlang:error({missing_required_field, hd(Keys)});
    <<>> -> erlang:error({missing_required_field, hd(Keys)});
    Value -> Value
  end.

get_bin(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    null -> Default;
    Value ->
      Bin = to_bin(Value),
      case trim_bin(Bin) of
        <<>> -> Default;
        Trimmed -> Trimmed
      end
  end.

get_int(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    Value when is_integer(Value) -> Value;
    Value when is_binary(Value) ->
      case catch binary_to_integer(trim_bin(Value)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    Value when is_list(Value) ->
      case catch list_to_integer(string:trim(Value)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

get_number(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    V when is_integer(V) -> V;
    V when is_float(V) -> V;
    _ -> Default
  end.

get_list(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    null -> Default;
    Value when is_list(Value) -> Value;
    Value -> [Value]
  end.

get_bool(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    "true" -> true;
    "false" -> false;
    _ -> Default
  end.

find_any(Map0, Keys0) ->
  Map = ensure_map(Map0),
  Keys = expand_keys(Keys0),
  find_any_keys(Map, Keys).

find_any_keys(_Map, []) -> undefined;
find_any_keys(Map, [Key | Rest]) ->
  case maps:find(Key, Map) of
    {ok, Value} -> Value;
    error -> find_any_keys(Map, Rest)
  end.

expand_keys(Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Key of
        K when is_atom(K) -> [K, atom_to_binary(K, utf8) | Acc];
        K when is_binary(K) ->
          Atom = catch binary_to_existing_atom(K, utf8),
          case is_atom(Atom) of
            true -> [K, Atom | Acc];
            false -> [K | Acc]
          end;
        Other -> [Other | Acc]
      end
    end,
    [],
    Keys
  ).

is_bullet_line(<<"- ", _/binary>>) -> true;
is_bullet_line(<<"* ", _/binary>>) -> true;
is_bullet_line(<<"? ", _/binary>>) -> true;
is_bullet_line(_) -> false.

strip_bullet(<<"- ", Rest/binary>>) -> trim_bin(Rest);
strip_bullet(<<"* ", Rest/binary>>) -> trim_bin(Rest);
strip_bullet(<<226,128,162,32, Rest/binary>>) -> trim_bin(Rest);
strip_bullet(Line) -> trim_bin(Line).

trim_bin(Bin0) ->
  trim_right(trim_left(to_bin(Bin0))).

trim_left(<<C, Rest/binary>>) when C =:= 32; C =:= 9; C =:= 10; C =:= 13 ->
  trim_left(Rest);
trim_left(Bin) ->
  Bin.

trim_right(Bin) ->
  case byte_size(Bin) of
    0 -> <<>>;
    Size ->
      Last = binary:at(Bin, Size - 1),
      case (Last =:= 32) orelse (Last =:= 9) orelse (Last =:= 10) orelse (Last =:= 13) of
        true -> trim_right(binary:part(Bin, 0, Size - 1));
        false -> Bin
      end
  end.

normalize_newlines(Bin) ->
  binary:replace(binary:replace(Bin, <<"\r\n">>, <<"\n">>, [global]), <<"\r">>, <<"\n">>, [global]).

ensure_list_of_maps(List) when is_list(List) -> [ensure_map(Item) || Item <- List];
ensure_list_of_maps(_) -> [].

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) ->
  case lists:all(fun (Item) -> is_tuple(Item) andalso tuple_size(Item) =:= 2 end, L) of
    true -> maps:from_list(L);
    false -> #{}
  end;
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(F) when is_float(F) -> iolist_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

now_ts() -> erlang:system_time(millisecond) / 1000.0.

