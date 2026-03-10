-module(openagentic_case_store_run_finalize_success).
-export([finalize_run_success/9]).

finalize_run_success(RootDir, CaseId, CaseDir, Task0, Version, Run0, Attempt0, Delivery0, Input0) ->
  Delivery = openagentic_case_store_common_core:ensure_map(Delivery0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  Now = openagentic_case_store_common_meta:now_ts(),
  TaskId = openagentic_case_store_common_meta:id_of(Task0),
  RunId = openagentic_case_store_common_meta:id_of(Run0),
  AttemptId = openagentic_case_store_common_meta:id_of(Attempt0),
  ScratchDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(openagentic_case_store_common_lookup:get_in_map(Attempt0, [links, scratch_ref], <<>>))]),
  ok = openagentic_case_store_run_finalize_failure:write_attempt_delivery_files(ScratchDir, Delivery),
  ArtifactRefs = openagentic_case_store_run_artifacts:promote_attempt_delivery(CaseDir, TaskId, RunId, AttemptId, Delivery, Now),
  PreviousReports = lists:reverse(openagentic_case_store_repo_readers:read_task_fact_reports(CaseDir, TaskId)),
  ReportId = openagentic_case_store_common_meta:new_id(<<"report">>),
  {SupersedesReportId, ReportLineageId} =
    case PreviousReports of
      [PreviousReport | _] ->
        PrevLineageId = openagentic_case_store_common_lookup:get_in_map(PreviousReport, [ext, report_lineage_id], openagentic_case_store_common_meta:id_of(PreviousReport)),
        {openagentic_case_store_common_meta:id_of(PreviousReport), PrevLineageId};
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
        openagentic_case_store_repo_persist:update_object(
          openagentic_case_store_common_core:ensure_map(PreviousReport0),
          Now,
          fun (Obj) ->
            Obj#{ext => maps:merge(maps:get(ext, Obj, #{}), #{superseded_by_report_id => ReportId})}
          end
        ),
      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:fact_report_file(CaseDir, TaskId, openagentic_case_store_common_meta:id_of(PreviousReport1)), PreviousReport1)
    end,
    ReportsToSupersede
  ),
  FactReport =
    openagentic_case_store_run_artifacts:build_fact_report(
      CaseId,
      TaskId,
      RunId,
      AttemptId,
      openagentic_case_store_common_meta:id_of(Version),
      ReportId,
      Delivery,
      ArtifactRefs,
      SupersedesReportId,
      ReportLineageId,
      Now
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:fact_report_file(CaseDir, TaskId, ReportId), FactReport),
  {UrgentBrief0, UrgentMail} = openagentic_case_store_run_urgent_brief:maybe_build_urgent_brief_mail(CaseId, Task0, Run0, Attempt0, FactReport, Delivery, Now),
  {FactReport1, UrgentBrief} =
    case UrgentBrief0 of
      undefined -> {FactReport, undefined};
      _ ->
        UrgentBriefId = openagentic_case_store_common_meta:id_of(UrgentBrief0),
        ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:exception_brief_file(CaseDir, TaskId, UrgentBriefId), UrgentBrief0),
        FactReportUpdated = openagentic_case_store_repo_persist:update_object(FactReport, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{urgent_brief_id => UrgentBriefId})} end),
        ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:fact_report_file(CaseDir, TaskId, ReportId), FactReportUpdated),
        {FactReportUpdated, UrgentBrief0}
    end,
  ok = openagentic_case_store_run_failure_mail:maybe_persist_mail(CaseDir, UrgentMail),
  ok = maybe_append_urgent_brief_timeline(CaseDir, CaseId, TaskId, RunId, openagentic_case_store_common_meta:id_of(FactReport1), UrgentBrief, Delivery, Now),
  Attempt1 =
    openagentic_case_store_repo_persist:update_object(
      Attempt0,
      Now,
      fun (Obj) ->
        Obj#{
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"succeeded">>, ended_at => Now, promoted_artifact_refs => [openagentic_case_store_common_meta:id_of(Artifact) || Artifact <- ArtifactRefs]}
            )
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_attempt_file(CaseDir, TaskId, AttemptId), Attempt1),
  Run1 =
    openagentic_case_store_repo_persist:update_object(
      Run0,
      Now,
      fun (Obj) ->
        RunStatus =
          case openagentic_case_store_run_failure_classify:delivery_needs_followup(Delivery) of
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
                attempt_count => openagentic_case_store_common_lookup:get_in_map(Attempt1, [spec, attempt_index], 1),
                last_attempt_status => <<"succeeded">>,
                completed_at => Now,
                result_summary => openagentic_case_store_common_lookup:get_bin(Delivery, [result_summary], <<"monitoring run completed">>)
              }
            )
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_file(CaseDir, TaskId, RunId), Run1),
  Task1 =
    openagentic_case_store_repo_persist:update_object(
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
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), Task1),
  ok = maybe_refresh_case_aggregates(RootDir, CaseId, Task0, Task1, UrgentMail),
  Overview = maybe_response_overview(RootDir, CaseId, Input),
  {ok, openagentic_case_store_common_meta:compact_map(#{task => Task1, run => Run1, run_attempt => Attempt1, fact_report => FactReport1, urgent_brief => UrgentBrief, overview => Overview})}.

maybe_refresh_case_aggregates(RootDir, CaseId, Task0, Task1, UrgentMail) ->
  case should_refresh_case_aggregates(Task0, Task1, UrgentMail) of
    true ->
      ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
      openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId);
    false ->
      ok
  end.

should_refresh_case_aggregates(Task0, Task1, UrgentMail) ->
  Status0 = openagentic_case_store_common_lookup:get_in_map(Task0, [state, status], undefined),
  Status1 = openagentic_case_store_common_lookup:get_in_map(Task1, [state, status], undefined),
  case UrgentMail of
    undefined -> not (Status0 =:= <<"active">> andalso Status1 =:= <<"active">>);
    _ -> true
  end.

maybe_response_overview(RootDir, CaseId, Input) ->
  case maps:get(include_overview, Input, true) of
    false -> undefined;
    _ -> openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
  end.

maybe_append_urgent_brief_timeline(_CaseDir, _CaseId, _TaskId, _RunId, _ReportId, undefined, _Delivery, _Now) ->
  ok;
maybe_append_urgent_brief_timeline(CaseDir, CaseId, TaskId, RunId, ReportId, UrgentBrief, Delivery, Now) ->
  AlertSummary = openagentic_case_store_common_lookup:get_bin(Delivery, [alert_summary], <<"urgent monitoring brief triggered">>),
  openagentic_case_store_timeline:append_best_effort(
    CaseDir,
    openagentic_case_store_timeline:new_event(
      CaseId,
      <<"urgent_brief_triggered">>,
      AlertSummary,
      [
        #{type => <<"monitoring_task">>, id => TaskId},
        #{type => <<"monitoring_run">>, id => RunId},
        #{type => <<"fact_report">>, id => ReportId},
        #{type => <<"urgent_brief">>, id => openagentic_case_store_common_meta:id_of(UrgentBrief)}
      ],
      undefined,
      Now
    )
  ).

