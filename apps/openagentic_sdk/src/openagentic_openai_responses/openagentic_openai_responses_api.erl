-module(openagentic_openai_responses_api).

-export([complete/1, query/2, maybe_debug_http_request/2]).

-define(DEFAULT_BASE_URL, "https://api.openai.com/v1").
-define(DEFAULT_TIMEOUT_MS, 60000).
-define(DEFAULT_STREAM_READ_TIMEOUT_MS, 300000).

complete(Req0) ->
  Req = openagentic_openai_responses_utils:ensure_map(Req0),
  case {openagentic_openai_responses_utils:get_req(api_key, Req), openagentic_openai_responses_utils:get_req(model, Req)} of
    {{ok, ApiKey0}, {ok, Model0}} ->
      ApiKey = openagentic_openai_responses_utils:to_list(ApiKey0),
      Model = openagentic_openai_responses_utils:to_bin(Model0),
      BaseUrl = openagentic_openai_responses_utils:to_list(maps:get(base_url, Req, ?DEFAULT_BASE_URL)),
      TimeoutMs = maps:get(timeout_ms, Req, ?DEFAULT_TIMEOUT_MS),
      StreamReadTimeoutMs =
        maps:get(
          stream_read_timeout_ms,
          Req,
          maps:get(
            streamReadTimeoutMs,
            Req,
            maps:get(<<"stream_read_timeout_ms">>, Req, maps:get(<<"streamReadTimeoutMs">>, Req, ?DEFAULT_STREAM_READ_TIMEOUT_MS))
          )
        ),
      InputItems = maps:get(input, Req, []),
      Tools = maps:get(tools, Req, []),
      Prev = maps:get(previous_response_id, Req, maps:get(previousResponseId, Req, undefined)),
      Store = maps:get(store, Req, maps:get(<<"store">>, Req, undefined)),
      DefaultStore = openagentic_openai_responses_request:default_store(Req),
      ApiKeyHeader = openagentic_openai_responses_request:api_key_header(Req),
      OnDelta = maps:get(on_delta, Req, maps:get(onDelta, Req, undefined)),
      openagentic_openai_responses_request:do_complete(ApiKey, ApiKeyHeader, BaseUrl, Model, TimeoutMs, StreamReadTimeoutMs, InputItems, Tools, Prev, Store, DefaultStore, OnDelta);
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.

%% query/2: convenience wrapper for early scaffolding.

query(Prompt0, Opts0) ->
  Prompt = iolist_to_binary(Prompt0),
  Opts = openagentic_openai_responses_utils:ensure_map(Opts0),
  Req = #{
    api_key => maps:get(api_key, Opts, maps:get(<<"api_key">>, Opts, <<"">>)),
    model => maps:get(model, Opts, maps:get(<<"model">>, Opts, <<"">>)),
    base_url => maps:get(base_url, Opts, maps:get(<<"base_url">>, Opts, ?DEFAULT_BASE_URL)),
    timeout_ms => maps:get(timeout_ms, Opts, maps:get(<<"timeout_ms">>, Opts, ?DEFAULT_TIMEOUT_MS)),
    input => [#{role => <<"user">>, content => Prompt}],
    tools => maps:get(tools, Opts, maps:get(<<"tools">>, Opts, [])),
    previous_response_id => maps:get(previous_response_id, Opts, maps:get(<<"previous_response_id">>, Opts, undefined))
  },
  complete(Req).

maybe_debug_http_request(Url0, Headers0) ->
  case os:getenv("OPENAGENTIC_DEBUG_HTTP") of
    false -> ok;
    "" -> ok;
    "0" -> ok;
    _ ->
      %% Never print header values (may contain secrets). Print only header names and url.
      Url = openagentic_openai_responses_utils:to_list(Url0),
      HeaderNames = [K || {K, _V} <- openagentic_openai_responses_utils:ensure_list(Headers0)],
      io:format("debug.http url=~s headers=~p~n", [Url, HeaderNames]),
      ok
  end.
