-module(openagentic_provider_retry).

-export([call/2, call/3, parse_retry_after_ms/2]).

%% Kotlin parity (ProviderRetryOptions):
%% - max_retries (default 6)
%% - initial_backoff_ms (default 500)
%% - max_backoff_ms (default 30000)
%% - use_retry_after_ms (default true)

call(Fun, RetryCfg0) when is_function(Fun, 0) ->
  call(Fun, RetryCfg0, #{}).

call(Fun, RetryCfg0, Opts0) when is_function(Fun, 0) ->
  RetryCfg = ensure_map(RetryCfg0),
  Opts = ensure_map(Opts0),
  Max = int_default(RetryCfg, [max_retries, maxRetries, <<"max_retries">>, <<"maxRetries">>], 6),
  Initial = int_default(RetryCfg, [initial_backoff_ms, initialBackoffMs, <<"initial_backoff_ms">>, <<"initialBackoffMs">>], 500),
  MaxBackoff = int_default(RetryCfg, [max_backoff_ms, maxBackoffMs, <<"max_backoff_ms">>, <<"maxBackoffMs">>], 30000),
  UseRetryAfter = bool_default(RetryCfg, [use_retry_after_ms, useRetryAfterMs, <<"use_retry_after_ms">>, <<"useRetryAfterMs">>], true),

  NowFun = maps:get(now_fun, Opts, fun now_ms/0),
  SleepFun = maps:get(sleep_fun, Opts, fun sleep_ms/1),

  loop(Fun, 0, Max, erlang:max(0, Initial), erlang:max(0, MaxBackoff), UseRetryAfter, NowFun, SleepFun).

loop(Fun, Attempt, Max, Backoff, MaxBackoff, UseRetryAfter, NowFun, SleepFun) ->
  case Fun() of
    {ok, _} = Ok ->
      Ok;
    {error, Reason} = Err ->
      case retry_decision(Reason, UseRetryAfter, NowFun) of
        {retry, WaitOverride} when Attempt < Max ->
          WaitMs0 =
            case WaitOverride of
              undefined -> Backoff;
              I when is_integer(I) -> I;
              _ -> Backoff
            end,
          WaitMs = erlang:min(erlang:max(0, WaitMs0), MaxBackoff),
          _ = maybe_sleep(WaitMs, SleepFun),
          NextBackoff =
            case Backoff =< 0 of
              true -> 0;
              false -> erlang:min(Backoff * 2, MaxBackoff)
            end,
          loop(Fun, Attempt + 1, Max, NextBackoff, MaxBackoff, UseRetryAfter, NowFun, SleepFun);
        _ ->
          Err
      end
  end.

maybe_sleep(WaitMs, SleepFun) when is_integer(WaitMs), WaitMs > 0 ->
  try
    SleepFun(WaitMs)
  catch
    _:_ -> ok
  end;
maybe_sleep(_WaitMs, _SleepFun) ->
  ok.

retry_decision(Reason, UseRetryAfter, NowFun) ->
  %% Mirror Kotlin's retryDecision() shape: allow transient network/provider failures.
  case Reason of
    {http_error, Status, Headers, _Body} ->
      case is_retryable_http_status(Status) of
        true ->
          case {Status, UseRetryAfter} of
            {429, true} ->
              Wait = parse_retry_after_ms(header_value(<<"retry-after">>, Headers), NowFun()),
              {retry, Wait};
            _ ->
              {retry, undefined}
          end;
        false ->
          no_retry
      end;
    {http_stream_error, _} ->
      {retry, undefined};
    {httpc_request_failed, _} ->
      {retry, undefined};
    stream_ended_without_response_completed ->
      {retry, undefined};
    {provider_error, ErrObj} ->
      MsgLower = string:lowercase(string:trim(to_bin(ErrObj))),
      case looks_like_transient_stream_failure(MsgLower) of
        true -> {retry, undefined};
        false -> no_retry
      end;
    _ ->
      MsgLower2 = string:lowercase(string:trim(to_bin(Reason))),
      case looks_like_transient_stream_failure(MsgLower2) of
        true -> {retry, undefined};
        false -> no_retry
      end
  end.

is_retryable_http_status(Status) when is_integer(Status) ->
  lists:member(Status, [408, 425, 429, 500, 502, 503, 504]);
is_retryable_http_status(_) ->
  false.

looks_like_transient_stream_failure(MsgLower) when is_binary(MsgLower) ->
  Deny =
    [
      <<"unauthorized">>,
      <<"forbidden">>,
      <<"authentication">>,
      <<"invalid api key">>,
      <<"api key">>,
      <<"permission">>,
      <<"quota">>,
      <<"insufficient">>,
      <<"billing">>,
      <<"payment">>,
      <<"bad request">>,
      <<"invalid request">>,
      <<"validation">>,
      <<"model not found">>,
      <<"unsupported">>
    ],
  case lists:any(fun (S) -> binary:match(MsgLower, S) =/= nomatch end, Deny) of
    true ->
      false;
    false ->
      Allow =
        [
          <<"stream ended unexpectedly">>,
          <<"unexpected end of stream">>,
          <<"stream ended without completed event">>,
          <<"timed out">>,
          <<"timeout">>,
          <<"connection reset">>,
          <<"connection aborted">>,
          <<"broken pipe">>,
          <<"reset by peer">>,
          <<"eof">>,
          <<"socket">>
        ],
      lists:any(fun (S) -> binary:match(MsgLower, S) =/= nomatch end, Allow)
  end;
looks_like_transient_stream_failure(Other) ->
  looks_like_transient_stream_failure(string:lowercase(string:trim(to_bin(Other)))).

%% Parse Retry-After header into milliseconds (capped to signed 32-bit), Kotlin parity.
parse_retry_after_ms(Header0, NowEpochMs0) ->
  NowEpochMs = ensure_int(NowEpochMs0, now_ms()),
  Raw = string:trim(to_bin(Header0)),
  case byte_size(Raw) of
    0 -> undefined;
    _ ->
      case parse_ms_suffix(Raw) of
        {ok, Ms} -> cap_ms(Ms);
        error ->
          case (catch binary_to_integer(Raw)) of
            Sec when is_integer(Sec) ->
              cap_ms(safe_mul_ms(Sec));
            _ ->
              parse_rfc1123_date(Raw, NowEpochMs)
          end
      end
  end.

parse_ms_suffix(Bin) ->
  %% e.g. "1500ms"
  case re:run(Bin, <<"^\\s*([0-9]+)\\s*ms\\s*$">>, [{capture, [1], binary}, caseless]) of
    {match, [Num]} ->
      case (catch binary_to_integer(Num)) of
        I when is_integer(I) -> {ok, I};
        _ -> error
      end;
    _ ->
      error
  end.

parse_rfc1123_date(RawBin, NowEpochMs) ->
  %% Use inets httpd_util parser if available.
  Raw = ensure_list(RawBin),
  try
    {{Y, M, D}, {H, Mi, S}} = httpd_util:convert_request_date(Raw),
    TargetSecs = calendar:datetime_to_gregorian_seconds({{Y, M, D}, {H, Mi, S}}),
    NowSecs = NowEpochMs div 1000,
    DeltaSecs = TargetSecs - NowSecs,
    case DeltaSecs > 0 of
      true -> cap_ms(DeltaSecs * 1000);
      false -> undefined
    end
  catch
    _:_ -> undefined
  end.

cap_ms(Ms0) ->
  Ms = ensure_int(Ms0, 0),
  case Ms < 0 of
    true -> 0;
    false ->
      %% Align with Kotlin: clamp to signed 32-bit max.
      Max = 2147483647,
      case Ms > Max of true -> Max; false -> Ms end
  end.

safe_mul_ms(Sec) when is_integer(Sec), Sec >= 0 ->
  %% avoid overflow
  case Sec > (9223372036854775807 div 1000) of
    true -> 9223372036854775807;
    false -> Sec * 1000
  end;
safe_mul_ms(_) ->
  0.

header_value(_KeyLower, []) -> undefined;
header_value(KeyLower0, Headers0) ->
  KeyLower = string:lowercase(to_bin(KeyLower0)),
  Headers = ensure_list(Headers0),
  case lists:dropwhile(
         fun (H) ->
           case H of
             {K0, _V0} ->
               string:lowercase(to_bin(K0)) =/= KeyLower;
             _ -> true
           end
         end,
         Headers
       ) of
    [{_K, V} | _] -> V;
    _ -> undefined
  end.

now_ms() ->
  erlang:system_time(millisecond).

sleep_ms(Ms) ->
  timer:sleep(Ms),
  ok.

ensure_int(I, _Default) when is_integer(I) -> I;
ensure_int(B, Default) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of
    X when is_integer(X) -> X;
    _ -> Default
  end;
ensure_int(L, Default) when is_list(L) ->
  ensure_int(unicode:characters_to_binary(L, utf8), Default);
ensure_int(_, Default) ->
  Default.

int_default(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  ensure_int(Val, Default).

bool_default(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    _ ->
      S = string:lowercase(string:trim(to_bin(Val))),
      lists:member(S, [<<"true">>, <<"1">>, <<"yes">>, <<"y">>, <<"ok">>])
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
