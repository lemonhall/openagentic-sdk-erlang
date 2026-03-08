-module(openagentic_openai_chat_completions_runtime).

-export([do_complete/6]).

-define(HTTPC_PROFILE, openagentic_chatcompletions).

do_complete(ApiKey, BaseUrl, Model, TimeoutMs, Messages, Tools) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Url = openagentic_http_url:join(BaseUrl, "/chat/completions"),
  Payload0 = #{model => Model, messages => Messages},
  Payload = case Tools of [] -> Payload0; _ -> Payload0#{tools => Tools} end,
  Body = openagentic_json:encode(Payload),
  Headers = [{"authorization", "Bearer " ++ ApiKey}, {"content-type", "application/json"}, {"accept", "application/json"}],
  HttpOptions = [{timeout, TimeoutMs}, {autoredirect, false}],
  Options = [{body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Options, ?HTTPC_PROFILE) of
    {ok, {{_Vsn, Status, _ReasonPhrase}, RespHeaders, RespBody}} ->
      case Status >= 400 of
        true -> {error, {http_error, Status, RespHeaders, RespBody}};
        false -> openagentic_openai_chat_completions_parse:parse_chat_response(RespBody)
      end;
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
    false -> "E:/erlang/httpc";
    V -> openagentic_openai_chat_completions_utils:to_list(V)
  end.

configure_proxy() ->
  case first_env(["HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy"]) of
    false -> ok;
    Url ->
      case parse_proxy_url(Url) of
        {ok, {Host, Port}} ->
          Opts = [{proxy, {{Host, Port}, []}}, {https_proxy, {{Host, Port}, []}}],
          case httpc:set_options(Opts, ?HTTPC_PROFILE) of ok -> ok; Err -> {error, {httpc_set_options_failed, Err}} end;
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
  Url = openagentic_openai_chat_completions_utils:to_list(Url0),
  try
    M = uri_string:parse(Url),
    Host0 = maps:get(host, M, undefined),
    Port0 = maps:get(port, M, undefined),
    case Host0 of
      undefined -> {error, no_host};
      Host ->
        Port = case Port0 of undefined -> 7897; P when is_integer(P) -> P; PStr -> list_to_integer(PStr) end,
        {ok, {Host, Port}}
    end
  catch
    _:T -> {error, T}
  end.
