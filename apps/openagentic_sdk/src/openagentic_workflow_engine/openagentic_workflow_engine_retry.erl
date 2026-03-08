-module(openagentic_workflow_engine_retry).
-export([run_step_executor_with_timeout/7,maybe_retry_transient_provider_error/6,retry_policy/1,maybe_sleep_ms/1,is_transient_provider_error/1]).

run_step_executor_with_timeout(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  TimeoutMs = openagentic_workflow_engine_state:step_timeout_ms(StepRaw, State0),
  Parent = self(),
  Ref = make_ref(),
  {Pid, MRef} =
    spawn_monitor(
      fun () ->
        Res = openagentic_workflow_engine_executor:run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
        Parent ! {step_exec_result, Ref, Res}
      end
    ),
  receive
    {step_exec_result, Ref, Res0} ->
      _ = erlang:demonitor(MRef, [flush]),
      Res0;
    {'DOWN', MRef, process, Pid, Reason} ->
      %% Result and DOWN may race; allow a small grace window to pick up the result if it was sent.
      receive
        {step_exec_result, Ref, Res1} -> Res1
      after 50 ->
        {error, {executor_crashed, Reason}}
      end
  after TimeoutMs ->
    _ = catch exit(Pid, kill),
    _ = erlang:demonitor(MRef, [flush]),
    {error, {step_timeout, TimeoutMs}}
  end.

maybe_retry_transient_provider_error(State0, StepId, StepRaw, Attempt, RetryCount0, Reason0) ->
  Reason = openagentic_workflow_engine_utils:to_bin(Reason0),
  case retry_policy(StepRaw) of
    #{enabled := true, max_retries := MaxRetries, backoff_ms := BackoffMs}
      when RetryCount0 < MaxRetries ->
      case is_transient_provider_error(Reason0) of
        true ->
          RetryCount = RetryCount0 + 1,
          ok =
            openagentic_workflow_engine_state:append_wf_event(
              State0,
              #{
                type => <<"workflow.step.retry">>,
                workflow_id => openagentic_workflow_engine_state:wf_id(State0),
                step_id => StepId,
                attempt => Attempt,
                retry_count => RetryCount,
                max_retries => MaxRetries,
                backoff_ms => BackoffMs,
                reason => Reason,
                retry_kind => <<"transient_provider_error">>
              }
            ),
          maybe_sleep_ms(BackoffMs),
          {retry, openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], [Reason])};
        false ->
          no_retry
      end;
    _ ->
      no_retry
  end.

retry_policy(StepRaw) ->
  Policy0 = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"retry_policy">>, retry_policy], #{})),
  Enabled = openagentic_workflow_engine_utils:to_bool_default(openagentic_workflow_engine_utils:get_any(Policy0, [<<"transient_provider_errors">>, transient_provider_errors], false), false),
  MaxRetries0 = openagentic_workflow_engine_utils:int_or_default(openagentic_workflow_engine_utils:get_any(Policy0, [<<"max_retries">>, max_retries], 0), 0),
  BackoffMs0 = openagentic_workflow_engine_utils:int_or_default(openagentic_workflow_engine_utils:get_any(Policy0, [<<"backoff_ms">>, backoff_ms], 1000), 1000),
  #{enabled => Enabled, max_retries => openagentic_workflow_engine_utils:clamp_int(MaxRetries0, 0, 3), backoff_ms => openagentic_workflow_engine_utils:clamp_int(BackoffMs0, 1, 30000)}.

maybe_sleep_ms(Ms) when is_integer(Ms), Ms > 0 ->
  timer:sleep(Ms),
  ok;

maybe_sleep_ms(_Ms) ->
  ok.

is_transient_provider_error(timeout) ->
  true;
is_transient_provider_error({step_timeout, _}) ->
  true;
is_transient_provider_error({http_stream_error, _}) ->
  true;
is_transient_provider_error({httpc_request_failed, _}) ->
  true;
is_transient_provider_error(stream_ended_without_response_completed) ->
  true;
is_transient_provider_error({provider_error, Reason}) ->
  is_transient_provider_error(Reason);
is_transient_provider_error({executor_crashed, Reason}) ->
  is_transient_provider_error(Reason);
is_transient_provider_error(Reason0) ->
  Reason = string:lowercase(string:trim(openagentic_workflow_engine_utils:to_bin(Reason0))),
  Deny =
    [
      <<"unauthorized">>,
      <<"forbidden">>,
      <<"authentication">>,
      <<"invalid api key">>,
      <<"permission">>,
      <<"quota">>,
      <<"billing">>,
      <<"payment">>,
      <<"bad request">>,
      <<"invalid request">>,
      <<"validation">>,
      <<"model not found">>,
      <<"unsupported">>
    ],
  Allow =
    [
      <<"timeout">>,
      <<"timed out">>,
      <<"stream ended without response completed">>,
      <<"http_stream_error">>,
      <<"connection reset">>,
      <<"connection aborted">>,
      <<"temporarily unavailable">>,
      <<"econnreset">>,
      <<"broken pipe">>
    ],
  (not lists:any(fun (Pat) -> binary:match(Reason, Pat) =/= nomatch end, Deny))
  andalso lists:any(fun (Pat) -> binary:match(Reason, Pat) =/= nomatch end, Allow).
