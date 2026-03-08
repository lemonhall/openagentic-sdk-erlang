-module(openagentic_provider_retry_test).

-include_lib("eunit/include/eunit.hrl").

parse_retry_after_ms_test() ->
  Now = 1000000,
  ?assertEqual(1500, openagentic_provider_retry:parse_retry_after_ms(<<"1500ms">>, Now)),
  ?assertEqual(3000, openagentic_provider_retry:parse_retry_after_ms(<<"3">>, Now)),
  ?assertEqual(undefined, openagentic_provider_retry:parse_retry_after_ms(<<>>, Now)),
  ?assertEqual(undefined, openagentic_provider_retry:parse_retry_after_ms(undefined, Now)),
  ok.

retry_uses_retry_after_header_test() ->
  put(waited, []),
  NowFun = fun () -> 1234 end,
  SleepFun =
    fun (Ms) ->
      L = case get(waited) of undefined -> []; V -> V end,
      put(waited, L ++ [Ms]),
      ok
    end,
  Attempts0 = 0,
  put(attempts, Attempts0),
  Fun =
    fun () ->
      A = case get(attempts) of undefined -> 0; V -> V end,
      put(attempts, A + 1),
      case A of
        0 ->
          {error, {http_error, 429, [{<<"retry-after">>, <<"100ms">>}], <<>>}};
        _ ->
          {ok, done}
      end
    end,
  RetryCfg = #{max_retries => 3, initial_backoff_ms => 500, max_backoff_ms => 30000, use_retry_after_ms => true},
  {ok, done} = openagentic_provider_retry:call(Fun, RetryCfg, #{now_fun => NowFun, sleep_fun => SleepFun}),
  ?assertEqual([100], get(waited)),
  ok.

retry_uses_backoff_when_no_retry_after_test() ->
  put(waited2, []),
  SleepFun =
    fun (Ms) ->
      L = case get(waited2) of undefined -> []; V -> V end,
      put(waited2, L ++ [Ms]),
      ok
    end,
  put(attempts2, 0),
  Fun =
    fun () ->
      A = case get(attempts2) of undefined -> 0; V -> V end,
      put(attempts2, A + 1),
      case A of
        0 ->
          {error, {http_stream_error, timeout}};
        _ ->
          {ok, ok}
      end
    end,
  RetryCfg = #{max_retries => 1, initial_backoff_ms => 500, max_backoff_ms => 30000, use_retry_after_ms => true},
  {ok, ok} = openagentic_provider_retry:call(Fun, RetryCfg, #{sleep_fun => SleepFun}),
  ?assertEqual([500], get(waited2)),
  ok.

invalid_api_key_does_not_retry_test() ->
  put(waited3, []),
  SleepFun =
    fun (Ms) ->
      L = case get(waited3) of undefined -> []; V -> V end,
      put(waited3, L ++ [Ms]),
      ok
    end,
  put(attempts3, 0),
  Fun =
    fun () ->
      A = case get(attempts3) of undefined -> 0; V -> V end,
      put(attempts3, A + 1),
      {error, {provider_error, <<"invalid api key">>}}
    end,
  RetryCfg = #{max_retries => 3, initial_backoff_ms => 500, max_backoff_ms => 30000, use_retry_after_ms => true},
  ?assertEqual({error, {provider_error, <<"invalid api key">>}}, openagentic_provider_retry:call(Fun, RetryCfg, #{sleep_fun => SleepFun})),
  ?assertEqual([], get(waited3)),
  ?assertEqual(1, get(attempts3)),
  ok.
