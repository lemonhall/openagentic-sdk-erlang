-module(openagentic_case_store_task_history_runs).
-export([build_historical_execution_summary/3, summarize_attempt/1, summarize_report/1, find_report/2, build_latest_exception_summary/2, build_latest_report_summary/1, build_recent_rectification_summary/1, build_task_failure_stats/2, count_failures_by_class/1]).

build_historical_execution_summary(Runs0, Attempts0, Reports0) ->
  Runs = [openagentic_case_store_common_core:ensure_map(Run) || Run <- Runs0],
  Attempts = [openagentic_case_store_common_core:ensure_map(Attempt) || Attempt <- Attempts0],
  Reports = [openagentic_case_store_common_core:ensure_map(Report) || Report <- Reports0],
  lists:sublist(
    [
      openagentic_case_store_common_meta:compact_map(
        #{
          run_id => openagentic_case_store_common_meta:id_of(Run),
          status => openagentic_case_store_common_lookup:get_in_map(Run, [state, status], undefined),
          planned_for_at => openagentic_case_store_common_lookup:get_in_map(Run, [spec, planned_for_at], undefined),
          attempt_count => openagentic_case_store_common_lookup:get_in_map(Run, [state, attempt_count], undefined),
          last_attempt_status => openagentic_case_store_common_lookup:get_in_map(Run, [state, last_attempt_status], undefined),
          result_summary => openagentic_case_store_common_lookup:get_in_map(Run, [state, result_summary], undefined),
          latest_attempt => summarize_attempt(openagentic_case_store_run_failure_classify:find_attempt(Attempts, openagentic_case_store_common_lookup:get_in_map(Run, [links, latest_attempt_id], undefined))),
          fact_report => summarize_report(find_report(Reports, openagentic_case_store_common_lookup:get_in_map(Run, [links, report_id], undefined)))
        }
      )
     || Run <- Runs
    ],
    5
  ).

summarize_attempt(undefined) -> #{};
summarize_attempt(Attempt0) ->
  Attempt = openagentic_case_store_common_core:ensure_map(Attempt0),
  openagentic_case_store_common_meta:compact_map(
    #{
      attempt_id => openagentic_case_store_common_meta:id_of(Attempt),
      status => openagentic_case_store_common_lookup:get_in_map(Attempt, [state, status], undefined),
      failure_class => openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_class], undefined),
      failure_summary => openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_summary], undefined),
      execution_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined),
      scratch_ref => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, scratch_ref], undefined)
    }
  ).

summarize_report(undefined) -> #{};
summarize_report(Report0) ->
  Report = openagentic_case_store_common_core:ensure_map(Report0),
  openagentic_case_store_common_meta:compact_map(
    #{
      report_id => openagentic_case_store_common_meta:id_of(Report),
      status => openagentic_case_store_common_lookup:get_in_map(Report, [state, status], undefined),
      quality_summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], undefined),
      alert_summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, alert_summary], undefined),
      report_lineage_id => openagentic_case_store_common_lookup:get_in_map(Report, [ext, report_lineage_id], undefined),
      supersedes_report_id => openagentic_case_store_common_lookup:get_in_map(Report, [ext, supersedes_report_id], undefined)
    }
  ).

find_report([], _ReportId) -> undefined;
find_report([Report | Rest], ReportId) ->
  case openagentic_case_store_common_meta:id_of(Report) =:= ReportId of
    true -> Report;
    false -> find_report(Rest, ReportId)
  end.

build_latest_exception_summary(Attempts0, Briefs0) ->
  Attempts = lists:reverse([openagentic_case_store_common_core:ensure_map(Attempt) || Attempt <- Attempts0]),
  Briefs = lists:reverse([openagentic_case_store_common_core:ensure_map(Brief) || Brief <- Briefs0]),
  case [Attempt || Attempt <- Attempts, openagentic_case_store_common_lookup:get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>] of
    [Attempt | _] ->
      AttemptId = openagentic_case_store_common_meta:id_of(Attempt),
      Brief =
        case [Item || Item <- Briefs, openagentic_case_store_common_lookup:get_in_map(Item, [links, attempt_id], undefined) =:= AttemptId] of
          [Item | _] -> Item;
          [] -> undefined
        end,
      openagentic_case_store_common_meta:compact_map(
        #{
          attempt_id => AttemptId,
          failure_class => openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_class], undefined),
          failure_summary => openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_summary], undefined),
          execution_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined),
          exception_brief_id =>
            case Brief of
              undefined -> undefined;
              _ -> openagentic_case_store_common_meta:id_of(Brief)
            end
        }
      );
    [] ->
      #{}
  end.

build_latest_report_summary(Reports0) ->
  Reports = lists:reverse([openagentic_case_store_common_core:ensure_map(Report) || Report <- Reports0]),
  case Reports of
    [Report | _] -> summarize_report(Report);
    [] -> #{}
  end.

build_recent_rectification_summary(Versions0) ->
  Versions = lists:reverse([openagentic_case_store_common_core:ensure_map(Version) || Version <- Versions0]),
  case Versions of
    [Current, Previous | _] ->
      openagentic_case_store_common_meta:compact_map(
        #{
          current_version_id => openagentic_case_store_common_meta:id_of(Current),
          previous_version_id => openagentic_case_store_common_meta:id_of(Previous),
          change_summary => openagentic_case_store_common_lookup:get_in_map(Current, [audit, change_summary], undefined),
          revised_by_op_id => openagentic_case_store_common_lookup:get_in_map(Current, [audit, revised_by_op_id], undefined)
        }
      );
    _ -> #{}
  end.

build_task_failure_stats(Runs0, Attempts0) ->
  Attempts = [openagentic_case_store_common_core:ensure_map(Attempt) || Attempt <- Attempts0],
  FailedAttempts = [Attempt || Attempt <- Attempts, openagentic_case_store_common_lookup:get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>],
  #{
    total_failed_attempts => length(FailedAttempts),
    consecutive_failure_count => openagentic_case_store_run_failure_classify:consecutive_failure_count(Runs0, Attempts0),
    latest_failure_class => openagentic_case_store_run_failure_classify:latest_failure_class(Attempts0),
    by_class => count_failures_by_class(FailedAttempts)
  }.

count_failures_by_class(Attempts0) ->
  lists:foldl(
    fun (Attempt0, Acc0) ->
      Attempt = openagentic_case_store_common_core:ensure_map(Attempt0),
      FailureClass = openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_class], <<"unknown">>),
      Prev = maps:get(FailureClass, Acc0, 0),
      Acc0#{FailureClass => Prev + 1}
    end,
    #{},
    Attempts0
  ).
