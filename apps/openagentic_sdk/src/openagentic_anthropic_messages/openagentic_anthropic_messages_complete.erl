-module(openagentic_anthropic_messages_complete).

-export([complete/1]).

-define(DEFAULT_BASE_URL, "https://api.anthropic.com").
-define(DEFAULT_ANTHROPIC_VERSION, "2023-06-01").
-define(DEFAULT_TIMEOUT_MS, 60000).
-define(DEFAULT_STREAM_READ_TIMEOUT_MS, 300000).
-define(DEFAULT_MAX_TOKENS, 16384).

complete(Req0) ->
  Req = openagentic_anthropic_messages_utils:ensure_map(Req0),
  case {
    openagentic_anthropic_messages_utils:get_req(api_key, Req),
    openagentic_anthropic_messages_utils:get_req(model, Req)
  } of
    {{ok, ApiKey0}, {ok, Model0}} ->
      ApiKey = openagentic_anthropic_messages_utils:to_list(ApiKey0),
      Model = openagentic_anthropic_messages_utils:to_bin(Model0),
      BaseUrl = openagentic_anthropic_messages_utils:to_list(maps:get(base_url, Req, ?DEFAULT_BASE_URL)),
      TimeoutMs = maps:get(timeout_ms, Req, ?DEFAULT_TIMEOUT_MS),
      StreamReadTimeoutMs = maps:get(
        stream_read_timeout_ms,
        Req,
        maps:get(
          streamReadTimeoutMs,
          Req,
          maps:get(<<"stream_read_timeout_ms">>, Req, maps:get(<<"streamReadTimeoutMs">>, Req, ?DEFAULT_STREAM_READ_TIMEOUT_MS))
        )
      ),
      Version = openagentic_anthropic_messages_utils:to_list(
        maps:get(anthropic_version, Req, maps:get(<<"anthropic_version">>, Req, ?DEFAULT_ANTHROPIC_VERSION))
      ),
      MaxTokens = maps:get(max_tokens, Req, maps:get(<<"max_tokens">>, Req, ?DEFAULT_MAX_TOKENS)),
      InputItems = maps:get(input, Req, []),
      Tools = maps:get(tools, Req, []),
      OnDelta = maps:get(on_delta, Req, maps:get(onDelta, Req, undefined)),
      Stream = is_function(OnDelta, 1),
      openagentic_anthropic_messages_request:do_complete(
        ApiKey,
        BaseUrl,
        Version,
        Model,
        MaxTokens,
        TimeoutMs,
        StreamReadTimeoutMs,
        InputItems,
        Tools,
        Stream,
        OnDelta
      );
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.
