-module(openagentic_case_store_run_failure_classify).
-export([derive_task_failure_outcome/3, consecutive_failure_count/2, latest_failure_class/1, find_attempt/2, classify_runtime_failure/1, runtime_failure_summary/2, contains_any_fragment/2, delivery_needs_followup/1, exception_severity/1]).

derive_task_failure_outcome(CaseDir, Task0, Now) ->
  TaskId = openagentic_case_store_common_meta:id_of(Task0),
  Runs = lists:reverse(openagentic_case_store_repo_readers:read_task_runs(CaseDir, TaskId)),
  Attempts = openagentic_case_store_repo_readers:read_task_run_attempts(CaseDir, TaskId),
  Count = consecutive_failure_count(Runs, Attempts),
  LatestFailureClass = latest_failure_class(Attempts),
  CurrentStatus = openagentic_case_store_common_lookup:get_in_map(Task0, [state, status], <<"active">>),
  case Count >= 3 of
    true ->
      MailObj =
        case CurrentStatus of
          <<"rectification_required">> -> undefined;
          _ -> openagentic_case_store_run_failure_mail:build_rectification_mail(openagentic_case_store_common_lookup:get_in_map(Task0, [links, case_id], undefined), Task0, LatestFailureClass, Count, Now)
        end,
      {<<"rectification_required">>, <<"rectification_required">>, MailObj};
    false when Count =:= 2 -> {<<"active">>, <<"flaky">>, undefined};
    false -> {<<"active">>, <<"degraded">>, undefined}
  end.

consecutive_failure_count(Runs0, Attempts0) ->
  Runs = [openagentic_case_store_common_core:ensure_map(R) || R <- Runs0],
  Attempts = [openagentic_case_store_common_core:ensure_map(A) || A <- Attempts0],
  consecutive_failure_count(Runs, Attempts, 0).

consecutive_failure_count([], _Attempts, Acc) -> Acc;
consecutive_failure_count([Run | Rest], Attempts, Acc) ->
  LatestAttemptId = openagentic_case_store_common_lookup:get_in_map(Run, [links, latest_attempt_id], undefined),
  case find_attempt(Attempts, LatestAttemptId) of
    undefined -> Acc;
    Attempt ->
      case openagentic_case_store_common_lookup:get_in_map(Attempt, [state, status], <<>>) of
        <<"failed">> -> consecutive_failure_count(Rest, Attempts, Acc + 1);
        _ -> Acc
      end
  end.

latest_failure_class(Attempts0) ->
  Attempts = lists:reverse([openagentic_case_store_common_core:ensure_map(Attempt) || Attempt <- Attempts0]),
  case [openagentic_case_store_common_lookup:get_in_map(Attempt, [state, failure_class], undefined) || Attempt <- Attempts, openagentic_case_store_common_lookup:get_in_map(Attempt, [state, status], <<>>) =:= <<"failed">>] of
    [FailureClass | _] -> FailureClass;
    [] -> undefined
  end.

find_attempt([], _AttemptId) -> undefined;
find_attempt([Attempt | Rest], AttemptId) ->
  case openagentic_case_store_common_meta:id_of(Attempt) =:= AttemptId of
    true -> Attempt;
    false -> find_attempt(Rest, AttemptId)
  end.

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
    case openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(Body)) of
      <<>> -> openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(Reason));
      Bin -> Bin
    end,
  case Candidate of
    <<>> -> <<"runtime error">>;
    _ -> Candidate
  end.

contains_any_fragment(Bin, Fragments) ->
  lists:any(fun (Fragment) -> binary:match(Bin, Fragment) =/= nomatch end, Fragments).

delivery_needs_followup(Delivery0) ->
  Delivery = openagentic_case_store_common_core:ensure_map(Delivery0),
  Facts = openagentic_case_store_common_core:ensure_list_of_maps(openagentic_case_store_common_lookup:get_in_map(Delivery, [facts], [])),
  lists:any(
    fun (Fact0) ->
      Fact = openagentic_case_store_common_core:ensure_map(Fact0),
      case string:lowercase(openagentic_case_store_common_lookup:get_bin(Fact, [alert_level, alertLevel], <<"normal">>)) of
        <<"normal">> -> false;
        <<"low">> -> false;
        _ -> true
      end
    end,
    Facts
  ).

exception_severity(<<"auth_expired">>) -> <<"high">>;
exception_severity(<<"rate_limited">>) -> <<"medium">>;
exception_severity(<<"source_unreachable">>) -> <<"medium">>;
exception_severity(<<"source_schema_changed">>) -> <<"high">>;
exception_severity(<<"data_conflict_unresolved">>) -> <<"high">>;
exception_severity(_) -> <<"medium">>.
