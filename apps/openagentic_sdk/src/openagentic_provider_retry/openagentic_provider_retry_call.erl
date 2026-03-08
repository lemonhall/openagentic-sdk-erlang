-module(openagentic_provider_retry_call).

-export([call/2, call/3]).

call(Fun, RetryCfg0) when is_function(Fun, 0) ->
  call(Fun, RetryCfg0, #{}).

call(Fun, RetryCfg0, Opts0) when is_function(Fun, 0) ->
  RetryCfg = openagentic_provider_retry_utils:ensure_map(RetryCfg0),
  Opts = openagentic_provider_retry_utils:ensure_map(Opts0),
  Max = openagentic_provider_retry_utils:int_default(RetryCfg, [max_retries, maxRetries, <<"max_retries">>, <<"maxRetries">>], 6),
  Initial = openagentic_provider_retry_utils:int_default(RetryCfg, [initial_backoff_ms, initialBackoffMs, <<"initial_backoff_ms">>, <<"initialBackoffMs">>], 500),
  MaxBackoff = openagentic_provider_retry_utils:int_default(RetryCfg, [max_backoff_ms, maxBackoffMs, <<"max_backoff_ms">>, <<"maxBackoffMs">>], 30000),
  UseRetryAfter = openagentic_provider_retry_utils:bool_default(RetryCfg, [use_retry_after_ms, useRetryAfterMs, <<"use_retry_after_ms">>, <<"useRetryAfterMs">>], true),
  NowFun = maps:get(now_fun, Opts, fun openagentic_provider_retry_utils:now_ms/0),
  SleepFun = maps:get(sleep_fun, Opts, fun openagentic_provider_retry_utils:sleep_ms/1),
  loop(Fun, 0, Max, erlang:max(0, Initial), erlang:max(0, MaxBackoff), UseRetryAfter, NowFun, SleepFun).

loop(Fun, Attempt, Max, Backoff, MaxBackoff, UseRetryAfter, NowFun, SleepFun) ->
  case Fun() of
    {ok, _} = Ok ->
      Ok;
    {error, Reason} = Err ->
      case openagentic_provider_retry_classify:retry_decision(Reason, UseRetryAfter, NowFun) of
        {retry, WaitOverride} when Attempt < Max ->
          WaitMs = pick_wait_ms(WaitOverride, Backoff, MaxBackoff),
          _ = maybe_sleep(WaitMs, SleepFun),
          loop(Fun, Attempt + 1, Max, next_backoff(Backoff, MaxBackoff), MaxBackoff, UseRetryAfter, NowFun, SleepFun);
        _ ->
          Err
      end
  end.

pick_wait_ms(WaitOverride, Backoff, MaxBackoff) ->
  WaitMs0 = case WaitOverride of undefined -> Backoff; I when is_integer(I) -> I; _ -> Backoff end,
  erlang:min(erlang:max(0, WaitMs0), MaxBackoff).

next_backoff(Backoff, _MaxBackoff) when Backoff =< 0 -> 0;
next_backoff(Backoff, MaxBackoff) -> erlang:min(Backoff * 2, MaxBackoff).

maybe_sleep(WaitMs, SleepFun) when is_integer(WaitMs), WaitMs > 0 ->
  try SleepFun(WaitMs) catch _:_ -> ok end;
maybe_sleep(_WaitMs, _SleepFun) ->
  ok.
