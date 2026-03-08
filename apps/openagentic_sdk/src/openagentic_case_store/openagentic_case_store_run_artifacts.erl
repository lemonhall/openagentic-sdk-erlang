-module(openagentic_case_store_run_artifacts).
-export([promote_attempt_delivery/6, copy_if_exists/2, build_promoted_artifact/7, build_external_artifact_refs/5, build_fact_report/11]).

promote_attempt_delivery(CaseDir, TaskId, RunId, AttemptId, Delivery, Now) ->
  DeliverDir = openagentic_case_store_repo_paths:deliverables_dir(CaseDir, TaskId, RunId),
  ok = filelib:ensure_dir(filename:join([DeliverDir, "x"])),
  ScratchDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(openagentic_case_store_repo_paths:attempt_scratch_ref(TaskId, RunId, AttemptId))]),
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
  RelPath = openagentic_case_store_repo_paths:deliverable_ref(TaskId, RunId, FileName),
  #{
    header => openagentic_case_store_common_meta:header(openagentic_case_store_common_meta:new_id(<<"artifact">>), <<"run_artifact">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{task_id => TaskId, run_id => RunId, source_attempt_id => AttemptId}),
    spec => #{title => FileName, kind => Kind, summary => Summary, path => RelPath},
    state => #{status => <<"promoted">>},
    audit => #{},
    ext => #{}
  }.

build_external_artifact_refs(TaskId, RunId, AttemptId, Artifacts0, Now) ->
  lists:map(
    fun(Artifact0) ->
      Artifact = openagentic_case_store_common_core:ensure_map(Artifact0),
      # {
        header => openagentic_case_store_common_meta:header(openagentic_case_store_common_meta:new_id(<<"artifact">>), <<"run_artifact">>, Now),
        links => openagentic_case_store_common_meta:compact_map(#{task_id => TaskId, run_id => RunId, source_attempt_id => AttemptId}),
        spec => openagentic_case_store_common_meta:compact_map(#{title => openagentic_case_store_common_lookup:get_bin(Artifact, [title], <<"artifact">>), kind => openagentic_case_store_common_lookup:get_bin(Artifact, [kind], <<"attachment">>), summary => openagentic_case_store_common_lookup:get_bin(Artifact, [summary], undefined), path => openagentic_case_store_common_lookup:get_bin(Artifact, [path], undefined)}),
        state => #{status => <<"indexed">>},
        audit => #{},
        ext => #{}
      }
    end,
    Artifacts0
  ).

build_fact_report(CaseId, TaskId, RunId, AttemptId, VersionId, ReportId, Delivery, ArtifactRefs, SupersedesReportId, ReportLineageId, Now) ->
  #{
    header => openagentic_case_store_common_meta:header(ReportId, <<"fact_report">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, task_id => TaskId, run_id => RunId, successful_attempt_id => AttemptId, pack_ids => []}),
    spec => openagentic_case_store_common_meta:compact_map(#{report_contract_ref => <<VersionId/binary, "#report_contract">>, artifact_refs => ArtifactRefs, observed_window => openagentic_case_store_common_lookup:get_in_map(Delivery, [observed_window], #{}), report_kind => openagentic_case_store_common_lookup:get_bin(Delivery, [report_kind], <<"routine_fact_report">>)}),
    state => openagentic_case_store_common_meta:compact_map(#{status => <<"submitted">>, submitted_at => Now, accepted_at => undefined, quality_summary => openagentic_case_store_common_lookup:get_bin(Delivery, [result_summary], undefined), alert_summary => openagentic_case_store_common_lookup:get_bin(Delivery, [alert_summary], undefined)}),
    audit => #{},
    ext => #{report_lineage_id => ReportLineageId, supersedes_report_id => SupersedesReportId, superseded_by_report_id => undefined}
  }.
