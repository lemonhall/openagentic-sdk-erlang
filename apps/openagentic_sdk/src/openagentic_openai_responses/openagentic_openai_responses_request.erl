-module(openagentic_openai_responses_request).

-export([do_complete/12, request_payload_for_test/5, build_headers_for_test/3, default_store/1, api_key_header/1, pick_first/2]).

-define(HTTPC_PROFILE, openagentic).

do_complete(ApiKey, ApiKeyHeader, BaseUrl, Model, TimeoutMs, StreamReadTimeoutMs, InputItems, Tools, Prev, Store, DefaultStore, OnDelta) ->
  ok = openagentic_openai_responses_runtime:ensure_httpc_started(),
  ok = openagentic_openai_responses_runtime:configure_proxy(),
  Url = openagentic_http_url:join(BaseUrl, "/responses"),
  Body = request_body(Model, InputItems, Tools, Prev, Store, DefaultStore),
  Headers = build_headers(ApiKeyHeader, ApiKey, true),
  _ = openagentic_openai_responses_api:maybe_debug_http_request(Url, Headers),
  %% Kotlin parity: disable automatic redirects (HttpURLConnection.instanceFollowRedirects=false).
  HttpOptions = [{timeout, TimeoutMs}, {autoredirect, false}],
  %% inets:httpc expects stream target to be `self` (atom) or `{self, once}`,
  %% not a pid like `self()`.
  Options = [{sync, false}, {stream, self}, {body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, ReqId} ->
      openagentic_openai_responses_stream:collect_stream(ReqId, StreamReadTimeoutMs, OnDelta);
    Error ->
      {error, {httpc_request_failed, Error}}
  end.

request_body(Model, InputItems0, Tools0, Prev, Store0, DefaultStore0) ->
  InputItems = openagentic_openai_responses_utils:ensure_list(InputItems0),
  Tools = openagentic_openai_responses_utils:ensure_list(Tools0),
  Store = store_flag(Store0, DefaultStore0),
  Payload0 = #{
    model => Model,
    input => InputItems,
    stream => true,
    store => Store
  },
  Payload1 =
    case Tools of
      [] -> Payload0;
      _ -> Payload0#{tools => Tools}
    end,
  Payload2 =
    case Prev of
      undefined -> Payload1;
      <<>> -> Payload1;
      "" -> Payload1;
      V -> Payload1#{previous_response_id => openagentic_openai_responses_utils:to_bin(V)}
    end,
  openagentic_json:encode(Payload2).

store_flag(Store0, DefaultStore0) ->
  DefaultStore = to_bool(DefaultStore0, true),
  case Store0 of
    undefined -> DefaultStore;
    null -> DefaultStore;
    V -> to_bool(V, DefaultStore)
  end.

default_store(Req) ->
  case pick_first(Req, [default_store, defaultStore, <<"default_store">>, <<"defaultStore">>]) of
    undefined -> true;
    V -> to_bool(V, true)
  end.

api_key_header(Req) ->
  H0 = pick_first(Req, [api_key_header, apiKeyHeader, <<"api_key_header">>, <<"apiKeyHeader">>]),
  H1 = string:trim(openagentic_openai_responses_utils:to_bin(H0)),
  case H1 of
    <<>> -> <<"authorization">>;
    <<"undefined">> -> <<"authorization">>;
    _ -> H1
  end.

pick_first(_Map, []) ->
  undefined;
pick_first(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_first(Map, Rest);
    V -> V
  end.

build_headers(ApiKeyHeader0, ApiKey, AcceptEventStream) ->
  ApiKeyHeader = openagentic_openai_responses_utils:to_list(string:trim(openagentic_openai_responses_utils:to_bin(ApiKeyHeader0))),
  HeaderLower = string:lowercase(ApiKeyHeader),
  KeyVal =
    case HeaderLower of
      "authorization" -> "Bearer " ++ ApiKey;
      _ -> ApiKey
    end,
  Base = [{ApiKeyHeader, KeyVal}, {"content-type", "application/json"}],
  case AcceptEventStream of
    true -> Base ++ [{"accept", "text/event-stream"}];
    false -> Base
  end.

to_bool(undefined, Default) -> Default;
to_bool(null, Default) -> Default;
to_bool(true, _Default) -> true;
to_bool(false, _Default) -> false;
to_bool(1, _Default) -> true;
to_bool(0, _Default) -> false;
to_bool(V, Default) ->
  S = string:lowercase(string:trim(openagentic_openai_responses_utils:to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"allow">> -> true;
    <<"ok">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.


request_payload_for_test(Model, InputItems0, Tools0, Prev, Req0) ->
  Req = openagentic_openai_responses_utils:ensure_map(Req0),
  Store0 = maps:get(store, Req, maps:get(<<"store">>, Req, undefined)),
  DefaultStore0 = default_store(Req),
  Store = store_flag(Store0, DefaultStore0),
  InputItems = openagentic_openai_responses_utils:ensure_list(InputItems0),
  Tools = openagentic_openai_responses_utils:ensure_list(Tools0),
  Payload0 = #{model => openagentic_openai_responses_utils:to_bin(Model), input => InputItems, stream => true, store => Store},
  Payload1 = case Tools of [] -> Payload0; _ -> Payload0#{tools => Tools} end,
  Payload2 =
    case Prev of
      undefined -> Payload1;
      <<>> -> Payload1;
      "" -> Payload1;
      V -> Payload1#{previous_response_id => openagentic_openai_responses_utils:to_bin(V)}
    end,
  Payload2.

build_headers_for_test(ApiKeyHeader0, ApiKey0, AcceptEventStream) ->
  build_headers(ApiKeyHeader0, openagentic_openai_responses_utils:to_list(ApiKey0), AcceptEventStream).
