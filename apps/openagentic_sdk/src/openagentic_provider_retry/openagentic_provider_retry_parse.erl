-module(openagentic_provider_retry_parse).

-export([header_value/2, parse_retry_after_ms/2]).

parse_retry_after_ms(Header0, NowEpochMs0) ->
  NowEpochMs = openagentic_provider_retry_utils:ensure_int(NowEpochMs0, openagentic_provider_retry_utils:now_ms()),
  Raw = string:trim(openagentic_provider_retry_utils:to_bin(Header0)),
  case byte_size(Raw) of
    0 -> undefined;
    _ ->
      case parse_ms_suffix(Raw) of
        {ok, Ms} -> cap_ms(Ms);
        error ->
          case (catch binary_to_integer(Raw)) of
            Sec when is_integer(Sec) -> cap_ms(safe_mul_ms(Sec));
            _ -> parse_rfc1123_date(Raw, NowEpochMs)
          end
      end
  end.

parse_ms_suffix(Bin) ->
  case re:run(Bin, <<"^\\s*([0-9]+)\\s*ms\\s*$">>, [{capture, [1], binary}, caseless]) of
    {match, [Num]} -> case (catch binary_to_integer(Num)) of I when is_integer(I) -> {ok, I}; _ -> error end;
    _ -> error
  end.

parse_rfc1123_date(RawBin, NowEpochMs) ->
  Raw = openagentic_provider_retry_utils:ensure_list(RawBin),
  try
    {{Y, M, D}, {H, Mi, S}} = httpd_util:convert_request_date(Raw),
    TargetSecs = calendar:datetime_to_gregorian_seconds({{Y, M, D}, {H, Mi, S}}),
    NowSecs = NowEpochMs div 1000,
    DeltaSecs = TargetSecs - NowSecs,
    case DeltaSecs > 0 of true -> cap_ms(DeltaSecs * 1000); false -> undefined end
  catch
    _:_ -> undefined
  end.

cap_ms(Ms0) ->
  Ms = openagentic_provider_retry_utils:ensure_int(Ms0, 0),
  case Ms < 0 of true -> 0; false -> erlang:min(Ms, 2147483647) end.

safe_mul_ms(Sec) when is_integer(Sec), Sec >= 0 ->
  case Sec > (9223372036854775807 div 1000) of true -> 9223372036854775807; false -> Sec * 1000 end;
safe_mul_ms(_) ->
  0.

header_value(_KeyLower, []) -> undefined;
header_value(KeyLower0, Headers0) ->
  KeyLower = string:lowercase(openagentic_provider_retry_utils:to_bin(KeyLower0)),
  Headers = openagentic_provider_retry_utils:ensure_list(Headers0),
  case lists:dropwhile(fun (H) -> case H of {K0, _V0} -> string:lowercase(openagentic_provider_retry_utils:to_bin(K0)) =/= KeyLower; _ -> true end end, Headers) of
    [{_K, V} | _] -> V;
    _ -> undefined
  end.
