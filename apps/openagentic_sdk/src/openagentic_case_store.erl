-module(openagentic_case_store).

-export([
  create_case_from_round/2,
  extract_candidates/2,
  approve_candidate/2,
  discard_candidate/2,
  get_case_overview/2
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
    ok = write_json(case_file(CaseDir), CaseObj),
    ok = write_json(round_file(CaseDir, RoundId), RoundObj),
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
              status => <<"active">>,
              health => <<"ok">>,
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
                schedule_policy => choose_map(Input, [schedule_policy, schedulePolicy], get_in_map(Candidate0, [spec, schedule_policy], default_schedule_policy(default_timezone(CaseSnapshot)))),
                report_contract => choose_map(Input, [report_contract, reportContract], get_in_map(Candidate0, [spec, report_contract], default_report_contract())),
                alert_rules => choose_map(Input, [alert_rules, alertRules], get_in_map(Candidate0, [spec, alert_rules], #{})),
                source_strategy => choose_map(Input, [source_strategy, sourceStrategy], get_in_map(Candidate0, [spec, source_strategy], #{})),
                tool_profile => choose_map(Input, [tool_profile, toolProfile], get_in_map(Candidate0, [spec, tool_profile], #{})),
                credential_requirements => choose_map(Input, [credential_requirements, credentialRequirements], get_in_map(Candidate0, [spec, credential_requirements], #{})),
                autonomy_policy => choose_map(Input, [autonomy_policy, autonomyPolicy], get_in_map(Candidate0, [spec, autonomy_policy], #{})),
                promotion_policy => choose_map(Input, [promotion_policy, promotionPolicy], get_in_map(Candidate0, [spec, promotion_policy], #{}))
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
      ok = write_json(task_file(CaseDir, TaskId), TaskObj),
      ok = write_json(task_version_file(CaseDir, TaskId, VersionId), TaskVersionObj),
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
      ok = write_json(CandidatePath, Candidate1),
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
  ok = write_json(CandidatePath, Candidate1),
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
  ok = write_json(candidate_file(CaseDir, CandidateId), CandidateObj),
  ok = write_json(mail_file(CaseDir, MailId), MailObj),
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

get_case_overview_map(RootDir, CaseId) ->
  {ok, CaseObj, CaseDir} = load_case(RootDir, CaseId),
  Rounds = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  Candidates = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"]))),
  Tasks = sort_by_created_at(read_task_objects(filename:join([CaseDir, "meta", "tasks"]))),
  Mail = sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "mail"]))),
  #{'case' => CaseObj, rounds => Rounds, candidates => Candidates, tasks => Tasks, mail => Mail}.

refresh_case_state(RootDir, CaseId) ->
  {ok, CaseObj0, CaseDir} = load_case(RootDir, CaseId),
  Tasks = read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  ActiveTaskCount = length([T || T <- Tasks, get_in_map(T, [state, status], <<>>) =:= <<"active">>]),
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
  write_json(case_file(CaseDir), CaseObj1).

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
          ok = write_json(Path, Mail1);
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

mail_file(CaseDir, MailId0) ->
  MailId = ensure_list(MailId0),
  filename:join([CaseDir, "meta", "mail", MailId ++ ".json"]).

ensure_case_layout(CaseDir) ->
  ensure_dirs(
    [
      filename:join([CaseDir, "meta", "rounds"]),
      filename:join([CaseDir, "meta", "candidates"]),
      filename:join([CaseDir, "meta", "tasks"]),
      filename:join([CaseDir, "meta", "mail"]),
      filename:join([CaseDir, "meta", "indexes"]),
      filename:join([CaseDir, "artifacts"]),
      filename:join([CaseDir, "workspaces"]),
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

normalize_candidate_specs([]) -> [];
normalize_candidate_specs(Items) when is_list(Items) -> [ensure_map(Item) || Item <- Items];
normalize_candidate_specs(_) -> [].

choose_map(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> ensure_map(Default);
    Value -> ensure_map(Value)
  end.

get_in_map(Map0, [Key], Default) -> maps:get(Key, ensure_map(Map0), Default);
get_in_map(Map0, [Key | Rest], Default) ->
  Map = ensure_map(Map0),
  case maps:get(Key, Map, undefined) of
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

