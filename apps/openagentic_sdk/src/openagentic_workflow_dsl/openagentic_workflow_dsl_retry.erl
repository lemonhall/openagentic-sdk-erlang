-module(openagentic_workflow_dsl_retry).
-export([normalize_retry_policy_raw/2, validate_retry_policy/4]).

validate_retry_policy(_Path, undefined, _StrictUnknown, Errors) -> {undefined, Errors};
validate_retry_policy(_Path, null, _StrictUnknown, Errors) -> {undefined, Errors};
validate_retry_policy(Path, Retry0, StrictUnknown, Errors0) ->
  {Retry, Errors1} = openagentic_workflow_dsl_utils:require_map(Path, Retry0, <<"retry_policy must be an object">>, Errors0),
  Allowed = [<<"transient_provider_errors">>, <<"max_retries">>, <<"backoff_ms">>],
  Errors2 = openagentic_workflow_dsl_utils:maybe_only_keys(StrictUnknown, Retry, Allowed, Path, Errors1),
  {TransientProviderErrors, Errors3} =
    case openagentic_workflow_dsl_utils:get_any(Retry, [<<"transient_provider_errors">>, transient_provider_errors], undefined) of
      undefined -> {false, Errors2};
      true -> {true, Errors2};
      false -> {false, Errors2};
      _ -> {false, [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".transient_provider_errors">>]), <<"invalid_type">>, <<"transient_provider_errors must be a boolean">>) | Errors2]}
    end,
  {MaxRetries, Errors4} = validate_retry_int(iolist_to_binary([Path, <<".max_retries">>]), openagentic_workflow_dsl_utils:get_any(Retry, [<<"max_retries">>, max_retries], undefined), 0, 0, 3, <<"max_retries must be an integer between 0 and 3">>, Errors3),
  {BackoffMs, Errors5} = validate_retry_int(iolist_to_binary([Path, <<".backoff_ms">>]), openagentic_workflow_dsl_utils:get_any(Retry, [<<"backoff_ms">>, backoff_ms], undefined), 1000, 1, 30000, <<"backoff_ms must be an integer between 1 and 30000">>, Errors4),
  {#{<<"transient_provider_errors">> => TransientProviderErrors, <<"max_retries">> => MaxRetries, <<"backoff_ms">> => BackoffMs}, Errors5}.

validate_retry_int(_Path, undefined, Default, _Min, _Max, _Msg, Errors) -> {Default, Errors};
validate_retry_int(_Path, Value, _Default, Min, Max, _Msg, Errors) when is_integer(Value), Value >= Min, Value =< Max -> {Value, Errors};
validate_retry_int(Path, Value, Default, _Min, _Max, Msg, Errors) when is_integer(Value) -> {Default, [openagentic_workflow_dsl_utils:err(Path, <<"out_of_range">>, Msg) | Errors]};
validate_retry_int(Path, _Value, Default, _Min, _Max, Msg, Errors) -> {Default, [openagentic_workflow_dsl_utils:err(Path, <<"invalid_type">>, Msg) | Errors]}.

normalize_retry_policy_raw(StepRaw, undefined) -> StepRaw;
normalize_retry_policy_raw(StepRaw, RetryPolicy) -> StepRaw#{<<"retry_policy">> => RetryPolicy}.
