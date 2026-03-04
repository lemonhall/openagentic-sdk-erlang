-module(openagentic_openai_chat_completions).

-behaviour(openagentic_provider).

-export([complete/1]).

-ifdef(TEST).
-export([
  responses_input_to_chat_messages_for_test/1,
  responses_tools_to_chat_tools_for_test/1,
  parse_chat_response_for_test/1
]).
-endif.

-define(DEFAULT_BASE_URL, "https://api.openai.com/v1").
-define(DEFAULT_TIMEOUT_MS, 60000).
-define(HTTPC_PROFILE, openagentic_chatcompletions).

%% OpenAI Chat Completions-compatible provider.
%%
%% Input is SDK "Responses-style" input items (same as Kotlin SDK core loop):
%% - role messages: #{role=>"user|assistant|system", content=>"..."}
%% - function_call: #{type=>"function_call", call_id=>"...", name=>"...", arguments=>"...(json string)..."}
%% - function_call_output: #{type=>"function_call_output", call_id=>"...", output=>"...(json string)..."}
%%
%% Request (map):
%% - api_key (required)
%% - model (required)
%% - base_url (optional; default https://api.openai.com/v1)
%% - timeout_ms (optional; default 60000)
%% - input (optional; default: [])
%% - tools (optional; Responses tool schemas; default: [])
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
      InputItems = ensure_list(maps:get(input, Req, [])),
      Tools0 = ensure_list(maps:get(tools, Req, [])),
      Messages = responses_input_to_chat_messages(InputItems),
      Tools = responses_tools_to_chat_tools(Tools0),
      do_complete(ApiKey, BaseUrl, Model, TimeoutMs, Messages, Tools);
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.

do_complete(ApiKey, BaseUrl, Model, TimeoutMs, Messages, Tools) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Url = openagentic_http_url:join(BaseUrl, "/chat/completions"),
  Payload0 = #{model => Model, messages => Messages},
  Payload =
    case Tools of
      [] -> Payload0;
      _ -> Payload0#{tools => Tools}
    end,
  Body = openagentic_json:encode(Payload),
  Headers = [
    {"authorization", "Bearer " ++ ApiKey},
    {"content-type", "application/json"},
    {"accept", "application/json"}
  ],
  %% Kotlin parity: disable automatic redirects (HttpURLConnection.instanceFollowRedirects=false).
  HttpOptions = [{timeout, TimeoutMs}, {autoredirect, false}],
  Options = [{body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, {{_Vsn, Status, _ReasonPhrase}, RespHeaders, RespBody}} ->
      case Status >= 400 of
        true -> {error, {http_error, Status, RespHeaders, RespBody}};
        false -> parse_chat_response(RespBody)
      end;
    Error ->
      {error, {httpc_request_failed, Error}}
  end.

%% ---- transforms ----

responses_input_to_chat_messages(InputItems0) ->
  InputItems = ensure_list(InputItems0),
  responses_input_to_chat_messages_loop(InputItems, [], []).

responses_input_to_chat_messages_loop([], PendingToolCallsRev, AccRev) ->
  AccRev2 =
    case PendingToolCallsRev of
      [] -> AccRev;
      _ -> [assistant_tool_calls(lists:reverse(PendingToolCallsRev)) | AccRev]
    end,
  lists:reverse(AccRev2);
responses_input_to_chat_messages_loop([Item0 | Rest], PendingToolCallsRev0, AccRev0) ->
  Item = ensure_map(Item0),
  Role = to_bin(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Type = to_bin(maps:get(type, Item, maps:get(<<"type">>, Item, <<>>))),
  case {Role, Type} of
    {<<>>, <<"function_call">>} ->
      CallId = to_bin(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, <<>>))),
      Name = to_bin(maps:get(name, Item, maps:get(<<"name">>, Item, <<>>))),
      Args = to_bin(maps:get(arguments, Item, maps:get(<<"arguments">>, Item, <<>>))),
      Tc = #{
        <<"id">> => CallId,
        <<"type">> => <<"function">>,
        <<"function">> => #{
          <<"name">> => Name,
          <<"arguments">> => Args
        }
      },
      responses_input_to_chat_messages_loop(Rest, [Tc | PendingToolCallsRev0], AccRev0);
    {<<>>, <<"function_call_output">>} ->
      CallId = to_bin(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, <<>>))),
      Out = to_bin(maps:get(output, Item, maps:get(<<"output">>, Item, <<>>))),
      AccRev1 =
        case PendingToolCallsRev0 of
          [] -> AccRev0;
          _ -> [assistant_tool_calls(lists:reverse(PendingToolCallsRev0)) | AccRev0]
        end,
      ToolMsg = #{<<"role">> => <<"tool">>, <<"tool_call_id">> => CallId, <<"content">> => Out},
      responses_input_to_chat_messages_loop(Rest, [], [ToolMsg | AccRev1]);
    {<<"system">>, _} ->
      Content = to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
      AccRev1 = flush_pending(PendingToolCallsRev0, AccRev0),
      responses_input_to_chat_messages_loop(Rest, [], [#{<<"role">> => <<"system">>, <<"content">> => Content} | AccRev1]);
    {<<"user">>, _} ->
      Content = to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
      AccRev1 = flush_pending(PendingToolCallsRev0, AccRev0),
      responses_input_to_chat_messages_loop(Rest, [], [#{<<"role">> => <<"user">>, <<"content">> => Content} | AccRev1]);
    {<<"assistant">>, _} ->
      Content = to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
      AccRev1 = flush_pending(PendingToolCallsRev0, AccRev0),
      responses_input_to_chat_messages_loop(Rest, [], [#{<<"role">> => <<"assistant">>, <<"content">> => Content} | AccRev1]);
    _ ->
      responses_input_to_chat_messages_loop(Rest, PendingToolCallsRev0, AccRev0)
  end.

flush_pending([], AccRev) -> AccRev;
flush_pending(PendingToolCallsRev, AccRev) ->
  [assistant_tool_calls(lists:reverse(PendingToolCallsRev)) | AccRev].

assistant_tool_calls(ToolCalls) ->
  #{
    <<"role">> => <<"assistant">>,
    <<"content">> => <<>>,
    <<"tool_calls">> => ToolCalls
  }.

responses_tools_to_chat_tools(Tools0) ->
  Tools = ensure_list(Tools0),
  lists:filtermap(
    fun (T0) ->
      T = ensure_map(T0),
      Name = to_bin(maps:get(name, T, maps:get(<<"name">>, T, <<>>))),
      case byte_size(string:trim(Name)) > 0 of
        false ->
          false;
        true ->
          Desc = to_bin(maps:get(description, T, maps:get(<<"description">>, T, <<>>))),
          Params = ensure_map(maps:get(parameters, T, maps:get(<<"parameters">>, T, #{}))),
          Tool = #{
            <<"type">> => <<"function">>,
            <<"function">> => #{
              <<"name">> => Name,
              <<"description">> => Desc,
              <<"parameters">> => Params
            }
          },
          {true, Tool}
      end
    end,
    Tools
  ).

%% ---- parse ----

parse_chat_response(RespBody0) ->
  RespBody = to_bin(RespBody0),
  try
    Root = openagentic_json:decode(RespBody),
    parse_chat_response_obj(Root)
  catch
    _:_ ->
      {error, {invalid_json_response, head_tail_preview(RespBody, 2000)}}
  end.

parse_chat_response_obj(Root0) ->
  Root = ensure_map(Root0),
  ResponseId = to_bin(maps:get(<<"id">>, Root, maps:get(id, Root, undefined))),
  Usage = ensure_map(maps:get(<<"usage">>, Root, maps:get(usage, Root, #{}))),
  Choices0 = ensure_list(maps:get(<<"choices">>, Root, maps:get(choices, Root, []))),
  FirstChoice = case Choices0 of [C | _] -> ensure_map(C); _ -> #{} end,
  Message0 = ensure_map(maps:get(<<"message">>, FirstChoice, maps:get(message, FirstChoice, #{}))),
  AssistantText = to_bin(maps:get(<<"content">>, Message0, maps:get(content, Message0, <<>>))),
  ToolCalls0 = ensure_list(maps:get(<<"tool_calls">>, Message0, maps:get(tool_calls, Message0, []))),
  ToolCalls = parse_tool_calls(ToolCalls0),
  {ok, #{
    assistant_text => AssistantText,
    tool_calls => ToolCalls,
    response_id => ResponseId,
    usage => Usage
  }}.

parse_tool_calls(ToolCalls0) ->
  ToolCalls = ensure_list(ToolCalls0),
  lists:filtermap(
    fun (Tc0) ->
      Tc = ensure_map(Tc0),
      Id = to_bin(maps:get(<<"id">>, Tc, maps:get(id, Tc, <<>>))),
      Fn0 = ensure_map(maps:get(<<"function">>, Tc, maps:get(function, Tc, #{}))),
      Name = to_bin(maps:get(<<"name">>, Fn0, maps:get(name, Fn0, <<>>))),
      ArgsStr = to_bin(maps:get(<<"arguments">>, Fn0, maps:get(arguments, Fn0, <<>>))),
      Args = parse_args(ArgsStr),
      case {byte_size(string:trim(Id)) > 0, byte_size(string:trim(Name)) > 0} of
        {true, true} -> {true, #{tool_use_id => Id, name => Name, arguments => Args}};
        _ -> false
      end
    end,
    ToolCalls
  ).

parse_args(Bin0) ->
  Bin = string:trim(to_bin(Bin0)),
  case byte_size(Bin) of
    0 -> #{};
    _ ->
      try
        Obj = openagentic_json:decode(Bin),
        ensure_map(Obj)
      catch
        _:_ -> #{}
      end
  end.

head_tail_preview(Bin0, MaxChars0) ->
  Bin = to_bin(Bin0),
  MaxChars = erlang:max(0, MaxChars0),
  case MaxChars =< 0 of
    true -> <<>>;
    false ->
      L = bin_to_list_safe(Bin),
      case length(L) =< MaxChars of
        true -> unicode:characters_to_binary(L, utf8);
        false ->
          HeadLen = MaxChars div 2,
          TailLen = MaxChars - HeadLen,
          Head = lists:sublist(L, HeadLen),
          Tail = lists:nthtail(length(L) - TailLen, L),
          unicode:characters_to_binary(Head ++ "\n…truncated…\n" ++ Tail, utf8)
      end
  end.

bin_to_list_safe(Bin) when is_binary(Bin) ->
  try unicode:characters_to_list(Bin, utf8) catch _:_ -> binary_to_list(Bin) end;
bin_to_list_safe(Other) ->
  ensure_list(Other).

%% ---- httpc helpers (mirrors openagentic_openai_responses minimal subset) ----

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

%% ---- test exports ----

-ifdef(TEST).
responses_input_to_chat_messages_for_test(Input) -> responses_input_to_chat_messages(Input).
responses_tools_to_chat_tools_for_test(Tools) -> responses_tools_to_chat_tools(Tools).
parse_chat_response_for_test(Body) -> parse_chat_response(Body).
-endif.

%% ---- misc ----

get_req(Key, Map) ->
  case maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)) of
    undefined -> {error, {missing, Key}};
    <<>> -> {error, {missing, Key}};
    "" -> {error, {missing, Key}};
    V -> {ok, V}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [B];
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(undefined) -> "";
to_list(null) -> "";
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
