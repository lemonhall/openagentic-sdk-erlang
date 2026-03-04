-module(openagentic_openai_responses).

-behaviour(openagentic_provider).

-export([complete/1, query/2]).

-ifdef(TEST).
-export([parse_assistant_text_for_test/1, parse_tool_calls_for_test/1]).
-endif.

-define(DEFAULT_BASE_URL, "https://api.openai.com/v1").
-define(DEFAULT_TIMEOUT_MS, 60000).
-define(HTTPC_PROFILE, openagentic).

%% complete/1: OpenAI Responses API (SSE streaming).
%%
%% Request (map):
%% - api_key (required)
%% - model (required)
%% - base_url (optional; default https://api.openai.com/v1)
%% - timeout_ms (optional; default 60000)
%% - input (optional; Responses input array; default: [])
%% - tools (optional; Responses tool schemas; default: [])
%% - previous_response_id (optional)
%% - store (optional boolean)
%%
%% Returns:
%% {ok, #{assistant_text := binary(), tool_calls := list(), response_id := binary()|undefined, usage := map()|undefined}}
%% | {error, Reason}
complete(Req0) ->
  Req = ensure_map(Req0),
  case {get_req(api_key, Req), get_req(model, Req)} of
    {{ok, ApiKey0}, {ok, Model0}} ->
      ApiKey = to_list(ApiKey0),
      Model = to_bin(Model0),
      BaseUrl = to_list(maps:get(base_url, Req, ?DEFAULT_BASE_URL)),
      TimeoutMs = maps:get(timeout_ms, Req, ?DEFAULT_TIMEOUT_MS),
      InputItems = maps:get(input, Req, []),
      Tools = maps:get(tools, Req, []),
      Prev = maps:get(previous_response_id, Req, maps:get(previousResponseId, Req, undefined)),
      Store = maps:get(store, Req, undefined),
      do_complete(ApiKey, BaseUrl, Model, TimeoutMs, InputItems, Tools, Prev, Store);
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.

%% query/2: convenience wrapper for early scaffolding.
query(Prompt0, Opts0) ->
  Prompt = iolist_to_binary(Prompt0),
  Opts = ensure_map(Opts0),
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

do_complete(ApiKey, BaseUrl, Model, TimeoutMs, InputItems, Tools, Prev, Store) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Url = BaseUrl ++ "/responses",
  Body = request_body(Model, InputItems, Tools, Prev, Store),
  Headers = [
    {"authorization", "Bearer " ++ ApiKey},
    {"content-type", "application/json"},
    {"accept", "text/event-stream"}
  ],
  HttpOptions = [{timeout, TimeoutMs}],
  Options = [{sync, false}, {stream, self()}, {body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, ReqId} ->
      collect_stream(ReqId, TimeoutMs);
    Error ->
      {error, {httpc_request_failed, Error}}
  end.

ensure_httpc_started() ->
  application:ensure_all_started(inets),
  application:ensure_all_started(ssl),
  DataDir = httpc_data_dir(),
  _ = inets:start(httpc, [{profile, ?HTTPC_PROFILE}, {data_dir, DataDir}]),
  ok.

httpc_data_dir() ->
  case os:getenv("OPENAGENTIC_HTTPC_DATA_DIR") of
    false ->
      "E:/erlang/httpc";
    V ->
      to_list(V)
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

request_body(Model, InputItems0, Tools0, Prev, Store) ->
  InputItems = ensure_list(InputItems0),
  Tools = ensure_list(Tools0),
  Payload0 = #{
    model => Model,
    input => InputItems,
    stream => true
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
      V -> Payload1#{previous_response_id => to_bin(V)}
    end,
  Payload =
    case Store of
      undefined -> Payload2;
      V2 -> Payload2#{store => V2}
    end,
  openagentic_json:encode(Payload).

collect_stream(ReqId, TimeoutMs) ->
  Sse0 = openagentic_sse:new(),
  collect_loop(ReqId, TimeoutMs, Sse0, #{delta_text => <<>>, last_response => undefined, failed => undefined}).

collect_loop(ReqId, TimeoutMs, SseState0, Acc0) ->
  receive
    {http, {ReqId, stream, Bin}} when is_binary(Bin) ->
      {SseState1, SseEvents} = openagentic_sse:feed(SseState0, Bin),
      Acc1 = handle_sse_events(SseEvents, Acc0),
      collect_loop(ReqId, TimeoutMs, SseState1, Acc1);
    {http, {ReqId, stream_end, _Trailers}} ->
      finalize_to_model_output(Acc0);
    {http, {ReqId, {error, Reason}}} ->
      {error, {http_stream_error, Reason}};
    {http, {ReqId, stream_start, _Headers}} ->
      collect_loop(ReqId, TimeoutMs, SseState0, Acc0);
    {http, {ReqId, {{_Vsn, Status, _ReasonPhrase}, _Headers, Body}}} ->
      {error, {unexpected_non_stream_response, Status, Body}};
    _Other ->
      collect_loop(ReqId, TimeoutMs, SseState0, Acc0)
  after TimeoutMs ->
    _ = (catch httpc:cancel_request(ReqId, ?HTTPC_PROFILE)),
    {error, timeout}
  end.

handle_sse_events(SseEvents, Acc0) ->
  lists:foldl(fun handle_one_sse/2, Acc0, SseEvents).

handle_one_sse(#{data := <<>>}, Acc) ->
  Acc;
handle_one_sse(#{data := <<" [DONE]">>}, Acc) ->
  Acc;
handle_one_sse(#{data := <<"[DONE]">>}, Acc) ->
  Acc;
handle_one_sse(#{data := Data}, Acc0) ->
  case maps:get(failed, Acc0, undefined) of
    undefined ->
      try
        Obj = openagentic_json:decode(Data),
        TypeBin = to_bin(maps:get(<<"type">>, Obj, maps:get(type, Obj, <<>>))),
        handle_openai_type(TypeBin, Obj, Acc0)
      catch
        _:_ ->
          Acc0
      end;
    _ ->
      Acc0
  end.

handle_openai_type(<<"response.output_text.delta">>, Obj, Acc0) ->
  Delta = to_bin(maps:get(<<"delta">>, Obj, maps:get(delta, Obj, <<>>))),
  Prev = maps:get(delta_text, Acc0, <<>>),
  Acc0#{delta_text := <<Prev/binary, Delta/binary>>};
handle_openai_type(<<"response.completed">>, Obj, Acc0) ->
  Resp = maps:get(<<"response">>, Obj, maps:get(response, Obj, #{})),
  Acc0#{last_response := Resp};
handle_openai_type(<<"error">>, Obj, Acc0) ->
  Acc0#{failed := Obj};
handle_openai_type(_, _Obj, Acc0) ->
  Acc0.

finalize_to_model_output(Acc0) ->
  case maps:get(failed, Acc0, undefined) of
    undefined ->
      Resp = maps:get(last_response, Acc0, undefined),
      case Resp of
        undefined ->
          {error, stream_ended_without_response_completed};
        _ ->
          ResponseId = to_bin(maps:get(<<"id">>, Resp, maps:get(id, Resp, undefined))),
          Usage = maps:get(<<"usage">>, Resp, maps:get(usage, Resp, undefined)),
          OutputItems = maps:get(<<"output">>, Resp, maps:get(output, Resp, [])),
          AssistantText =
            case parse_assistant_text(OutputItems) of
              <<>> -> maps:get(delta_text, Acc0, <<>>);
              T -> T
            end,
          ToolCalls = parse_tool_calls(OutputItems),
          {ok, #{
            assistant_text => AssistantText,
            tool_calls => ToolCalls,
            usage => ensure_map(Usage),
            response_id => ResponseId
          }}
      end;
    Err ->
      {error, {provider_error, Err}}
  end.

parse_assistant_text(OutputItems0) ->
  Items = ensure_list(OutputItems0),
  Parts =
    lists:foldl(
      fun (Item0, Acc) ->
        Item = ensure_map(Item0),
        case to_bin(maps:get(<<"type">>, Item, maps:get(type, Item, <<>>))) of
          <<"message">> ->
            Content = maps:get(<<"content">>, Item, maps:get(content, Item, [])),
            Acc ++ message_text_parts(Content);
          _ ->
            Acc
        end
      end,
      [],
      Items
    ),
  iolist_to_binary(Parts).

message_text_parts(Content0) ->
  Content = ensure_list(Content0),
  lists:foldl(
    fun (Part0, Acc) ->
      Part = ensure_map(Part0),
      case to_bin(maps:get(<<"type">>, Part, maps:get(type, Part, <<>>))) of
        <<"output_text">> ->
          Txt = maps:get(<<"text">>, Part, maps:get(text, Part, <<>>)),
          case Txt of
            <<>> -> Acc;
            _ -> Acc ++ [to_bin(Txt)]
          end;
        _ ->
          Acc
      end
    end,
    [],
    Content
  ).

parse_tool_calls(OutputItems0) ->
  Items = ensure_list(OutputItems0),
  lists:foldl(
    fun (Item0, Acc) ->
      Item = ensure_map(Item0),
      case to_bin(maps:get(<<"type">>, Item, maps:get(type, Item, <<>>))) of
        <<"function_call">> ->
          CallId = to_bin(maps:get(<<"call_id">>, Item, maps:get(call_id, Item, <<>>))),
          Name = to_bin(maps:get(<<"name">>, Item, maps:get(name, Item, <<>>))),
          ArgsEl = maps:get(<<"arguments">>, Item, maps:get(arguments, Item, #{})),
          Args =
            case ArgsEl of
              M when is_map(M) -> M;
              B when is_binary(B) -> parse_args(B);
              L when is_list(L) -> parse_args(iolist_to_binary(L));
              _ -> #{<<"_raw">> => to_bin(ArgsEl)}
            end,
          case {CallId, Name} of
            {<<>>, _} -> Acc;
            {_, <<>>} -> Acc;
            _ -> Acc ++ [#{tool_use_id => CallId, name => Name, arguments => ensure_map(Args)}]
          end;
        _ ->
          Acc
      end
    end,
    [],
    Items
  ).

parse_args(Bin0) ->
  Bin = string:trim(to_bin(Bin0)),
  case Bin of
    <<>> -> #{};
    _ ->
      try
        openagentic_json:decode(Bin)
      catch
        _:_ -> #{<<"_raw">> => Bin}
      end
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

get_req(Key, Opts) ->
  case maps:get(Key, Opts, undefined) of
    undefined -> {error, {missing, Key}};
    V -> {ok, V}
  end.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

-ifdef(TEST).
parse_assistant_text_for_test(OutputItems) ->
  parse_assistant_text(OutputItems).

parse_tool_calls_for_test(OutputItems) ->
  parse_tool_calls(OutputItems).
-endif.
