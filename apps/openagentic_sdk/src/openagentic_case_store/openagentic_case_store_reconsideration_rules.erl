-module(openagentic_case_store_reconsideration_rules).

-export([
  evaluate_completeness_rule/3,
  evaluate_inspection_rule/2,
  can_start_deferred_package/4
]).

evaluate_completeness_rule(Eval0, Rule0, Now) ->
  Eval = openagentic_case_store_common_core:ensure_map(Eval0),
  Rule = normalize_completeness_rule(Rule0),
  ReportIds = maps:get(report_ids, Eval, []),
  MissingRequirements = maps:get(missing_requirements, Eval, []),
  Passed =
    case maps:get(mode, Rule) of
      <<"min_report_count">> -> length(ReportIds) >= normalized_min_reports(Rule);
      _ -> MissingRequirements =:= []
    end,
  Status =
    case {Passed, ReportIds} of
      {true, _} -> <<"awaiting_inspection">>;
      {false, []} -> <<"collecting">>;
      {false, _} -> <<"insufficient">>
    end,
  #{
    passed => Passed,
    status => Status,
    missing_requirements => MissingRequirements,
    has_stale_requirements => has_stale_requirement(MissingRequirements),
    latest_ready_at => case Passed of true -> Now; false -> undefined end,
    rule => Rule
  }.

evaluate_inspection_rule(Context0, Rule0) ->
  Context = openagentic_case_store_common_core:ensure_map(Context0),
  Rule = normalize_inspection_rule(Rule0),
  Completeness = openagentic_case_store_common_core:ensure_map(maps:get(completeness, Context, #{})),
  Controversies = maps:get(controversies, Context, []),
  BlockingIssues = maps:get(blocking_issues, Context, maps:get(missing_requirements, Completeness, [])),
  Passed =
    case maps:get(passed, Completeness, false) of
      false -> false;
      true -> inspection_gate_passed(maps:get(mode, Rule), Controversies, BlockingIssues)
    end,
  #{
    passed => Passed,
    status => case Passed of true -> <<"ready_for_reconsideration">>; false -> <<"insufficient">> end,
    controversies => Controversies,
    blocking_issues => BlockingIssues,
    rule => Rule
  }.

can_start_deferred_package(Package0, Completeness0, LatestLivePackageId0, _Now) ->
  Package = openagentic_case_store_common_core:ensure_map(Package0),
  Completeness = openagentic_case_store_common_core:ensure_map(Completeness0),
  Status = openagentic_case_store_common_lookup:get_in_map(Package, [state, status], <<>>),
  CurrentPackageId = openagentic_case_store_common_meta:id_of(Package),
  LatestLivePackageId = normalize_package_id(LatestLivePackageId0),
  case is_superseded(Status, Package, CurrentPackageId, LatestLivePackageId) of
    true -> {error, reconsideration_package_superseded};
    false ->
      case Status of
        <<"ready">> -> start_gate_from_completeness(Completeness);
        <<"deferred">> -> start_gate_from_completeness(Completeness);
        _ -> {error, reconsideration_package_not_actionable}
      end
  end.

normalize_completeness_rule(Rule0) ->
  Rule = openagentic_case_store_common_core:ensure_map(Rule0),
  Mode = maps:get(mode, Rule, <<"all_required_reports_present">>),
  case Mode of
    <<"min_report_count">> -> Rule#{mode => Mode, min_reports => normalized_min_reports(Rule)};
    _ -> #{mode => <<"all_required_reports_present">>}
  end.

normalize_inspection_rule(Rule0) ->
  Rule = openagentic_case_store_common_core:ensure_map(Rule0),
  case maps:get(mode, Rule, <<"manual_inspection_required">>) of
    <<"require_controversies">> -> #{mode => <<"require_controversies">>};
    <<"require_no_blocking_issues">> -> #{mode => <<"require_no_blocking_issues">>};
    <<"require_controversies_and_no_blocking_issues">> -> #{mode => <<"require_controversies_and_no_blocking_issues">>};
    _ -> #{mode => <<"manual_inspection_required">>}
  end.

normalized_min_reports(Rule) ->
  Value = openagentic_case_store_common_lookup:get_number(Rule, [min_reports, minReports], 1),
  case erlang:trunc(Value) of
    Count when Count >= 0 -> Count;
    _ -> 0
  end.

inspection_gate_passed(<<"require_controversies">>, Controversies, _BlockingIssues) -> Controversies =/= [];
inspection_gate_passed(<<"require_no_blocking_issues">>, _Controversies, BlockingIssues) -> BlockingIssues =:= [];
inspection_gate_passed(<<"require_controversies_and_no_blocking_issues">>, Controversies, BlockingIssues) ->
  Controversies =/= [] andalso BlockingIssues =:= [];
inspection_gate_passed(_, _Controversies, _BlockingIssues) -> true.

start_gate_from_completeness(Completeness) ->
  case maps:get(has_stale_requirements, Completeness, false) of
    true -> {error, reconsideration_package_stale};
    false ->
      case maps:get(passed, Completeness, false) of
        true -> ok;
        false -> {error, reconsideration_package_not_actionable}
      end
  end.

is_superseded(<<"superseded">>, _Package, _CurrentPackageId, _LatestLivePackageId) -> true;
is_superseded(_Status, Package, CurrentPackageId, LatestLivePackageId) ->
  case maps:get(superseded_by_package_id, maps:get(ext, Package, #{}), undefined) of
    undefined ->
      LatestLivePackageId =/= undefined andalso LatestLivePackageId =/= CurrentPackageId;
    _ -> true
  end.

normalize_package_id(undefined) -> undefined;
normalize_package_id(PackageId) -> openagentic_case_store_common_core:to_bin(PackageId).

has_stale_requirement(MissingRequirements) ->
  lists:any(
    fun (Requirement0) ->
      Requirement = openagentic_case_store_common_core:ensure_map(Requirement0),
      maps:get(reason, Requirement, undefined) =:= <<"stale_report">>
    end,
    MissingRequirements
  ).
