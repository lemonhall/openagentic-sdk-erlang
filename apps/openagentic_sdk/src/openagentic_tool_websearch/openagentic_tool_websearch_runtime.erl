-module(openagentic_tool_websearch_runtime).

-export([http_request/5]).

-define(HTTPC_PROFILE, openagentic_websearch).
-define(REQUEST_TIMEOUT_MS, 60000).

http_request(Method, Url0, Headers0, Body0, Ctx0) ->
  Ctx = openagentic_tool_websearch_utils:ensure_map(Ctx0),
  case maps:get(websearch_transport, Ctx, undefined) of
    Fun when is_function(Fun, 4) ->
      Fun(Method, Url0, Headers0, Body0);
    _ ->
      ok = ensure_httpc_started(),
      ok = configure_proxy(),
      default_http_request(Method, Url0, Headers0, Body0)
  end.

ensure_httpc_started() ->
  application:ensure_all_started(inets),
  application:ensure_all_started(ssl),
  _ = inets:start(httpc, [{profile, ?HTTPC_PROFILE}, {data_dir, httpc_data_dir()}]),
  ok.

httpc_data_dir() ->
  case os:getenv("OPENAGENTIC_HTTPC_DATA_DIR") of
    false -> "E:/erlang/httpc";
    Value -> openagentic_tool_websearch_utils:to_list(Value)
  end.

configure_proxy() ->
  case first_env(["HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy"]) of
    false -> ok;
    Url ->
      case parse_proxy_url(Url) of
        {ok, {Host, Port}} ->
          Opts = [{proxy, {{Host, Port}, []}}, {https_proxy, {{Host, Port}, []}}],
          _ = httpc:set_options(Opts, ?HTTPC_PROFILE),
          ok;
        _ -> ok
      end
  end.

first_env([]) -> false;
first_env([Key | Rest]) ->
  case os:getenv(Key) of
    false -> first_env(Rest);
    "" -> first_env(Rest);
    Value -> Value
  end.

parse_proxy_url(Url0) ->
  Url = openagentic_tool_websearch_utils:to_list(Url0),
  try
    Parsed = uri_string:parse(Url),
    case maps:get(host, Parsed, undefined) of
      undefined -> {error, no_host};
      Host ->
        Port = parse_proxy_port(maps:get(port, Parsed, undefined)),
        {ok, {Host, Port}}
    end
  catch
    _:Type -> {error, Type}
  end.

parse_proxy_port(undefined) -> 7897;
parse_proxy_port(Port) when is_integer(Port) -> Port;
parse_proxy_port(PortStr) -> list_to_integer(PortStr).

default_http_request(get, Url0, Headers0, _Body0) ->
  Url = binary_to_list(openagentic_tool_websearch_utils:to_bin(Url0)),
  case httpc:request(get, {Url, Headers0}, [{timeout, ?REQUEST_TIMEOUT_MS}], [{body_format, binary}], ?HTTPC_PROFILE) of
    {ok, {{_, Status, _}, RespHeaders, RespBody}} -> {ok, {Status, RespHeaders, RespBody}};
    Err -> {error, Err}
  end;
default_http_request(post, Url0, Headers0, Body0) ->
  Url = binary_to_list(openagentic_tool_websearch_utils:to_bin(Url0)),
  case httpc:request(post, {Url, Headers0, "application/json", Body0}, [{timeout, ?REQUEST_TIMEOUT_MS}], [{body_format, binary}], ?HTTPC_PROFILE) of
    {ok, {{_, Status, _}, RespHeaders, RespBody}} -> {ok, {Status, RespHeaders, RespBody}};
    Err -> {error, Err}
  end;
default_http_request(Method, _Url0, _Headers0, _Body0) ->
  {error, {unsupported_method, Method}}.
