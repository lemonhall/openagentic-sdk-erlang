-module(openagentic_openai_responses_runtime).

-export([ensure_httpc_started/0, configure_proxy/0]).

-define(HTTPC_PROFILE, openagentic).

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
      openagentic_openai_responses_utils:to_list(V)
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
  Url = openagentic_openai_responses_utils:to_list(Url0),
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
