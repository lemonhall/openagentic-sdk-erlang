-module(openagentic_case_store_run_finalize_success).
-export([finalize_run_success/8]).

finalize_run_success(RootDir, CaseId, CaseDir, Task0, Version, Run0, Attempt0, Delivery0) ->
  Delivery = openagentic_case_store_common_core:ensure_map(Delivery0),
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
  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  {ok, #{task => Task1, run => Run1, run_attempt => Attempt1, fact_report => FactReport, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}.
