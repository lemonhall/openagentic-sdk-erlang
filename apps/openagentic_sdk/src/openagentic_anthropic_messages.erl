-module(openagentic_anthropic_messages).

-behaviour(openagentic_provider).

-export([complete/1]).

-define(DEFAULT_BASE_URL, "https://api.anthropic.com").
-define(DEFAULT_ANTHROPIC_VERSION, "2023-06-01").
-define(DEFAULT_TIMEOUT_MS, 60000).
-define(DEFAULT_STREAM_READ_TIMEOUT_MS, 300000).
-define(DEFAULT_MAX_TOKENS, 16384).
-define(HTTPC_PROFILE, openagentic).

complete(Req0) ->
  Req = ensure_map(Req0),
  case {get_req(api_key, Req), get_req(model, Req)} of
    {{ok, ApiKey0}, {ok, Model0}} ->
      ApiKey = to_list(ApiKey0),
      Model = to_bin(Model0),
      BaseUrl = to_list(maps:get(base_url, Req, ?DEFAULT_BASE_URL)),
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
      Version = to_list(maps:get(anthropic_version, Req, maps:get(<<"anthropic_version">>, Req, ?DEFAULT_ANTHROPIC_VERSION))),
      MaxTokens = maps:get(max_tokens, Req, maps:get(<<"max_tokens">>, Req, ?DEFAULT_MAX_TOKENS)),
      InputItems = maps:get(input, Req, []),
      Tools = maps:get(tools, Req, []),
      OnDelta = maps:get(on_delta, Req, maps:get(onDelta, Req, undefined)),
      Stream = is_function(OnDelta, 1),
      do_complete(ApiKey, BaseUrl, Version, Model, MaxTokens, TimeoutMs, StreamReadTimeoutMs, InputItems, Tools, Stream, OnDelta);
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.

do_complete(ApiKey, BaseUrl, Version, Model, MaxTokens, TimeoutMs, StreamReadTimeoutMs, InputItems, Tools, Stream, OnDelta) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Url = BaseUrl ++ "/v1/messages",
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
  HttpOptions = [{timeout, TimeoutMs}],
  case Stream of
    false ->
      Options = [{sync, true}, {body_format, binary}],
      case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
        {ok, {{_Vsn, Status, _ReasonPhrase}, RespHeaders, RespBody}} when is_integer(Status) ->
          case Status >= 400 of
            true -> {error, {http_error, Status, RespHeaders, RespBody}};
            false -> parse_message_response(RespBody)
          end;
        Err ->
          {error, {httpc_request_failed, Err}}
      end;
    true ->
      Options = [{sync, false}, {stream, self()}, {body_format, binary}],
      case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
        {ok, ReqId} ->
          collect_stream(ReqId, StreamReadTimeoutMs, OnDelta);
        Err ->
          {error, {httpc_request_failed, Err}}
      end
  end.

parse_message_response(Body) ->
  try
    Root = ensure_map(openagentic_json:decode(Body)),
    MsgId = maps:get(<<"id">>, Root, undefined),
    Usage = maps:get(<<"usage">>, Root, undefined),
    Content = ensure_list(maps:get(<<"content">>, Root, [])),
    {ok, openagentic_anthropic_parsing:anthropic_content_to_model_output(Content, ensure_map(Usage), MsgId)}
  catch
    _:_ ->
      {error, {provider_error, <<"invalid JSON response">>}}
  end.

collect_stream(ReqId, TimeoutMs, OnDelta) ->
  Sse0 = openagentic_sse:new(),
  Dec0 = openagentic_anthropic_sse_decoder:new(),
  collect_loop(ReqId, TimeoutMs, Sse0, Dec0, OnDelta).

collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta) ->
  receive
    {http, {ReqId, stream, Bin}} when is_binary(Bin) ->
      {SseState1, SseEvents} = openagentic_sse:feed(SseState0, Bin),
      {Dec1, _} = handle_sse_events(SseEvents, Dec0, OnDelta),
      collect_loop(ReqId, TimeoutMs, SseState1, Dec1, OnDelta);
    {http, {ReqId, stream_end, _Trailers}} ->
      {_, FlushEvents} = openagentic_sse:end_of_input(SseState0),
      {Dec1, _} = handle_sse_events(FlushEvents, Dec0, OnDelta),
      openagentic_anthropic_sse_decoder:finish(Dec1);
    {http, {ReqId, {error, Reason}}} ->
      {error, {http_stream_error, Reason}};
    {http, {ReqId, stream_start, _Headers}} ->
      collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta);
    {http, {ReqId, {{_Vsn, Status, _ReasonPhrase}, Headers, Body}}} ->
      {error, {http_error, Status, Headers, Body}};
    _Other ->
      collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta)
  after TimeoutMs ->
    _ = (catch httpc:cancel_request(ReqId, ?HTTPC_PROFILE)),
    {error, timeout}
  end.

handle_sse_events(SseEvents, Dec0, OnDelta) ->
  lists:foldl(
    fun (Ev, {DecAcc0, _}) ->
      {DecAcc1, Deltas} = openagentic_anthropic_sse_decoder:on_sse_event(Ev, DecAcc0),
      _ =
        case OnDelta of
          F when is_function(F, 1) ->
            lists:foreach(fun (D) -> (catch F(D)) end, Deltas),
            ok;
          _ ->
            ok
        end,
      {DecAcc1, ok}
    end,
    {Dec0, ok},
    SseEvents
  ).

ensure_httpc_started() ->
  application:ensure_all_started(inets),
  application:ensure_all_started(ssl),
  DataDir = httpc_data_dir(),
  _ = inets:start(httpc, [{profile, ?HTTPC_PROFILE}, {data_dir, DataDir}]),
  ok.

httpc_data_dir() ->
  case os:getenv("OPENAGENTIC_HTTPC_DATA_DIR") of
    false -> "E:/erlang/httpc";
    V -> to_list(V)
  end.

configure_proxy() ->
  ProxyUrl =
    first_env([
      "HTTPS_PROXY",
      "HTTP_PROXY",
      "https_proxy",
      "http_proxy"
    ]),
  case ProxyUrl of
    false ->
      ok;
    Url ->
      case parse_proxy_url(Url) of
        {ok, {Host, Port}} ->
          Opts = [
            {proxy, {{Host, Port}, []}},
            {https_proxy, {{Host, Port}, []}}
          ],
          case httpc:set_options(Opts, ?HTTPC_PROFILE) of
            ok -> ok;
            Err -> {error, {httpc_set_options_failed, Err}}
          end;
        {error, Reason} ->
          {error, {invalid_proxy, Reason}}
      end
  end.

first_env([]) -> false;
first_env([K | T]) ->
  case os:getenv(K) of
    false -> first_env(T);
    "" -> first_env(T);
    V -> V
  end.

parse_proxy_url(Url0) ->
  Url = to_list(Url0),
  try
    M = uri_string:parse(Url),
    Host0 = maps:get(host, M, undefined),
    Port0 = maps:get(port, M, undefined),
    case Host0 of
      undefined ->
        {error, no_host};
      Host ->
        Port =
          case Port0 of
            undefined -> 7897;
            P when is_integer(P) -> P;
            PStr -> list_to_integer(PStr)
          end,
        {ok, {Host, Port}}
    end
  catch
    _:T ->
      {error, T}
  end.

get_req(Key, Map) ->
  case maps:get(Key, Map, maps:get(list_to_binary(atom_to_list(Key)), Map, undefined)) of
    undefined -> {error, {missing, Key}};
    null -> {error, {missing, Key}};
    <<>> -> {error, {missing, Key}};
    "" -> {error, {missing, Key}};
    V -> {ok, V}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

