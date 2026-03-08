-module(openagentic_anthropic_messages_request).

-export([do_complete/11]).

-define(HTTPC_PROFILE, openagentic).

do_complete(ApiKey, BaseUrl, Version, Model, MaxTokens, TimeoutMs, StreamReadTimeoutMs, InputItems, Tools, Stream, OnDelta) ->
  ok = openagentic_anthropic_messages_http:ensure_httpc_started(),
  ok = openagentic_anthropic_messages_http:configure_proxy(),
  Url = openagentic_http_url:join(BaseUrl, "/v1/messages"),
  {System, Messages} = openagentic_anthropic_parsing:responses_input_to_messages(InputItems),
  AnthTools = openagentic_anthropic_parsing:responses_tools_to_anthropic_tools(Tools),
  Payload0 = #{model => Model, max_tokens => MaxTokens, messages => Messages},
  Payload1 = case System of undefined -> Payload0; _ -> Payload0#{system => System} end,
  Payload2 = case AnthTools of [] -> Payload1; _ -> Payload1#{tools => AnthTools} end,
  Payload = case Stream of true -> Payload2#{stream => true}; false -> Payload2 end,
  Body = openagentic_json:encode(Payload),
  Headers0 = [
    {"content-type", "application/json"},
    {"x-api-key", ApiKey},
    {"anthropic-version", Version}
  ],
  Headers = case Stream of true -> Headers0 ++ [{"accept", "text/event-stream"}]; false -> Headers0 end,
  HttpOptions = [{timeout, TimeoutMs}, {autoredirect, false}],
  case Stream of
    false -> request_sync(Url, Headers, Body, HttpOptions);
    true -> request_stream(Url, Headers, Body, HttpOptions, StreamReadTimeoutMs, OnDelta)
  end.

request_sync(Url, Headers, Body, HttpOptions) ->
  Options = [{sync, true}, {body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, {{_Vsn, Status, _ReasonPhrase}, RespHeaders, RespBody}} when is_integer(Status) ->
      case Status >= 400 of
        true -> {error, {http_error, Status, RespHeaders, RespBody}};
        false -> openagentic_anthropic_messages_response:parse_message_response(RespBody)
      end;
    Err ->
      {error, {httpc_request_failed, Err}}
  end.

request_stream(Url, Headers, Body, HttpOptions, StreamReadTimeoutMs, OnDelta) ->
  Options = [{sync, false}, {stream, self}, {body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, ReqId} ->
      openagentic_anthropic_messages_stream:collect_stream(ReqId, StreamReadTimeoutMs, OnDelta);
    Err ->
      {error, {httpc_request_failed, Err}}
  end.
