-module(openagentic_case_store_run_parse_main).
-export([parse_monitoring_delivery/4, normalize_monitoring_facts/4, normalize_evidence_refs/1, normalize_monitoring_artifacts/2, ensure_map_or_path/1]).

parse_monitoring_delivery(Output0, TaskId, RunId, Now) ->
  case openagentic_case_store_run_inputs:parse_json_object(Output0) of
    {error, _} ->
      {error, <<"report_quality_insufficient">>, <<"monitoring delivery must be one JSON object">>};
    {ok, Obj0} ->
      Obj = openagentic_case_store_common_core:ensure_map(Obj0),
      ReportMarkdown = openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_lookup:get_bin(Obj, [report_markdown, reportMarkdown], <<>>)),
      Facts0 = openagentic_case_store_common_lookup:get_list(Obj, [facts], []),
      Artifacts0 = openagentic_case_store_common_lookup:get_list(Obj, [artifacts], []),
      case {byte_size(ReportMarkdown) > 0, is_list(Facts0), is_list(Artifacts0)} of
        {true, true, true} ->
          Facts = normalize_monitoring_facts(Facts0, TaskId, RunId, Now),
          case openagentic_case_store_run_inputs:has_traceable_source(Facts) of
            false ->
              {error, <<"report_quality_insufficient">>, <<"facts.json requires at least one traceable source reference">>};
            true ->
              {ok,
               #{
                 report_markdown => ReportMarkdown,
                 facts => Facts,
                 artifacts => normalize_monitoring_artifacts(Artifacts0, Now),
                 result_summary => openagentic_case_store_common_lookup:get_bin(Obj, [result_summary, resultSummary], <<"monitoring run completed">>),
                 alert_summary => openagentic_case_store_common_lookup:get_bin(Obj, [alert_summary, alertSummary], undefined),
                 report_kind => openagentic_case_store_common_lookup:get_bin(Obj, [report_kind, reportKind], <<"routine_fact_report">>),
                 observed_window => openagentic_case_store_run_inputs:normalize_observed_window(openagentic_case_store_common_lookup:choose_map(Obj, [observed_window, observedWindow], #{}), Facts, Now)
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
  Fact = openagentic_case_store_common_core:ensure_map(Fact0),
  SourceUrl = openagentic_case_store_common_lookup:get_bin(Fact, [source_url, sourceUrl, url], undefined),
  EvidenceRefs0 = openagentic_case_store_common_lookup:get_list(Fact, [evidence_refs, evidenceRefs], []),
  EvidenceRefs =
    case {EvidenceRefs0, SourceUrl} of
      {[], Url} when is_binary(Url), Url =/= <<>> -> [#{kind => <<"url">>, ref => Url}];
      _ -> normalize_evidence_refs(EvidenceRefs0)
    end,
  ValueSummary = openagentic_case_store_common_lookup:get_bin(Fact, [value_summary, valueSummary], <<>>),
  Title =
    case openagentic_case_store_common_lookup:get_bin(Fact, [title], undefined) of
      undefined when ValueSummary =/= <<>> -> ValueSummary;
      undefined -> <<"Fact">>;
      Value -> Value
    end,
  Fact1 =
    openagentic_case_store_common_meta:compact_map(
      #{
        fact_id => openagentic_case_store_common_lookup:get_bin(Fact, [fact_id, factId], openagentic_case_store_common_meta:new_id(<<"fact">>)),
        task_id => TaskId,
        run_id => RunId,
        observed_at => openagentic_case_store_common_lookup:get_number(Fact, [observed_at, observedAt], Now),
        collected_at => openagentic_case_store_common_lookup:get_number(Fact, [collected_at, collectedAt], Now),
        title => Title,
        fact_type => openagentic_case_store_common_lookup:get_bin(Fact, [fact_type, factType], <<"observation">>),
        source => openagentic_case_store_common_lookup:get_bin(Fact, [source], openagentic_case_store_common_lookup:get_bin(Fact, [source_name, sourceName], undefined)),
        source_url => SourceUrl,
        collection_method => openagentic_case_store_common_lookup:get_bin(Fact, [collection_method, collectionMethod], <<"agent_monitoring">>),
        value_summary => ValueSummary,
        change_summary => openagentic_case_store_common_lookup:get_bin(Fact, [change_summary, changeSummary], <<>>),
        alert_level => openagentic_case_store_common_lookup:get_bin(Fact, [alert_level, alertLevel], <<"normal">>),
        confidence_note => openagentic_case_store_common_lookup:get_bin(Fact, [confidence_note, confidenceNote], <<"not_provided">>),
        evidence_refs => EvidenceRefs
      }
    ),
  normalize_monitoring_facts(Rest, TaskId, RunId, Now, [Fact1 | Acc]).

normalize_evidence_refs(Refs0) ->
  lists:map(
    fun (Ref0) when is_binary(Ref0); is_list(Ref0) -> #{kind => <<"text">>, ref => openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(Ref0))};
        (Ref0) ->
      Ref = openagentic_case_store_common_core:ensure_map(Ref0),
      openagentic_case_store_common_meta:compact_map(#{kind => openagentic_case_store_common_lookup:get_bin(Ref, [kind], <<"text">>), ref => openagentic_case_store_common_lookup:get_bin(Ref, [ref, value, url], undefined)})
    end,
    openagentic_case_store_common_core:ensure_list(Refs0)
  ).

normalize_monitoring_artifacts(Artifacts0, Now) ->
  normalize_monitoring_artifacts(Artifacts0, Now, []).

normalize_monitoring_artifacts([], _Now, Acc) ->
  lists:reverse(Acc);
normalize_monitoring_artifacts([Artifact0 | Rest], Now, Acc) ->
  Artifact = ensure_map_or_path(Artifact0),
  Path = openagentic_case_store_common_lookup:get_bin(Artifact, [path, url, source_url], undefined),
  Title =
    case openagentic_case_store_common_lookup:get_bin(Artifact, [title], undefined) of
      undefined when Path =/= undefined -> Path;
      undefined -> <<"artifact">>;
      Value -> Value
    end,
  Artifact1 =
    openagentic_case_store_common_meta:compact_map(
      #{
        artifact_id => openagentic_case_store_common_lookup:get_bin(Artifact, [artifact_id, artifactId], openagentic_case_store_common_meta:new_id(<<"artifact">>)),
        title => Title,
        kind => openagentic_case_store_common_lookup:get_bin(Artifact, [kind], <<"attachment">>),
        summary => openagentic_case_store_common_lookup:get_bin(Artifact, [summary], undefined),
        path => Path,
        created_at => openagentic_case_store_common_lookup:get_number(Artifact, [created_at, createdAt], Now)
      }
    ),
  normalize_monitoring_artifacts(Rest, Now, [Artifact1 | Acc]).

ensure_map_or_path(Value) when is_map(Value) -> Value;
ensure_map_or_path(Value) when is_binary(Value); is_list(Value) -> #{path => openagentic_case_store_common_core:to_bin(Value)};
ensure_map_or_path(Value) -> openagentic_case_store_common_core:ensure_map(Value).
