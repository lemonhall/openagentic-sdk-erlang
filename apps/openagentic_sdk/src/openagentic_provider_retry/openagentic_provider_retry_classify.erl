-module(openagentic_provider_retry_classify).

-export([retry_decision/3]).

retry_decision(Reason, UseRetryAfter, NowFun) ->
  case Reason of
    {http_error, Status, Headers, _Body} -> retry_http_error(Status, Headers, UseRetryAfter, NowFun);
    {http_stream_error, _} -> {retry, undefined};
    {httpc_request_failed, _} -> {retry, undefined};
    stream_ended_without_response_completed -> {retry, undefined};
    {provider_error, ErrObj} -> retry_message(ErrObj);
    _ -> retry_message(Reason)
  end.

retry_http_error(Status, Headers, true, NowFun) when Status =:= 429 ->
  Wait = openagentic_provider_retry_parse:parse_retry_after_ms(openagentic_provider_retry_parse:header_value(<<"retry-after">>, Headers), NowFun()),
  case is_retryable_http_status(Status) of true -> {retry, Wait}; false -> no_retry end;
retry_http_error(Status, _Headers, _UseRetryAfter, _NowFun) ->
  case is_retryable_http_status(Status) of true -> {retry, undefined}; false -> no_retry end.

retry_message(Msg0) ->
  Msg = string:lowercase(string:trim(openagentic_provider_retry_utils:to_bin(Msg0))),
  case looks_like_transient_stream_failure(Msg) of true -> {retry, undefined}; false -> no_retry end.

is_retryable_http_status(Status) when is_integer(Status) ->
  lists:member(Status, [408, 425, 429, 500, 502, 503, 504]);
is_retryable_http_status(_) ->
  false.

looks_like_transient_stream_failure(MsgLower) when is_binary(MsgLower) ->
  Deny = [<<"unauthorized">>, <<"forbidden">>, <<"authentication">>, <<"invalid api key">>, <<"api key">>, <<"permission">>, <<"quota">>, <<"insufficient">>, <<"billing">>, <<"payment">>, <<"bad request">>, <<"invalid request">>, <<"validation">>, <<"model not found">>, <<"unsupported">>],
  case lists:any(fun (S) -> binary:match(MsgLower, S) =/= nomatch end, Deny) of
    true -> false;
    false ->
      Allow = [<<"stream ended unexpectedly">>, <<"unexpected end of stream">>, <<"stream ended without completed event">>, <<"timed out">>, <<"timeout">>, <<"connection reset">>, <<"connection aborted">>, <<"broken pipe">>, <<"reset by peer">>, <<"eof">>, <<"socket">>],
      lists:any(fun (S) -> binary:match(MsgLower, S) =/= nomatch end, Allow)
  end;
looks_like_transient_stream_failure(Other) ->
  looks_like_transient_stream_failure(string:lowercase(string:trim(openagentic_provider_retry_utils:to_bin(Other)))).
