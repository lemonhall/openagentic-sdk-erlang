-module(openagentic_tool_webfetch_tavily_support).

-export([tool_dotenv/1, tavily_extract_endpoint/1, first_non_blank/1, http_request/5, trim_bin/1]).

tool_dotenv(Ctx0) ->
  Ctx = openagentic_tool_webfetch_runtime:ensure_map(Ctx0),
  case maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, undefined)) of
    undefined -> #{};
    null -> #{};
    false -> #{};
    <<>> -> #{};
    "" -> #{};
    ProjectDir0 ->
      ProjectDir = string:trim(openagentic_tool_webfetch_runtime:to_bin(ProjectDir0)),
      case byte_size(ProjectDir) > 0 of
        false -> #{};
        true -> openagentic_dotenv:load(filename:join([openagentic_tool_webfetch_runtime:to_list(ProjectDir), ".env"]))
      end
  end.

tavily_extract_endpoint(undefined) -> <<"https://api.tavily.com/extract">>;
tavily_extract_endpoint(null) -> <<"https://api.tavily.com/extract">>;
tavily_extract_endpoint(false) -> <<"https://api.tavily.com/extract">>;
tavily_extract_endpoint(<<>>) -> <<"https://api.tavily.com/extract">>;
tavily_extract_endpoint("") -> <<"https://api.tavily.com/extract">>;
tavily_extract_endpoint(Url0) ->
  Url1 = string:trim(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  Url = trim_trailing_slash(Url1),
  case openagentic_tool_webfetch_sanitize:ends_with(Url, <<"/extract">>) of
    true -> Url;
    false ->
      case openagentic_tool_webfetch_sanitize:ends_with(Url, <<"/search">>) of
        true -> <<(binary:part(Url, 0, byte_size(Url) - 7))/binary, "/extract">>;
        false -> openagentic_tool_webfetch_runtime:to_bin(openagentic_http_url:join(Url, <<"extract">>))
      end
  end.

trim_trailing_slash(Bin0) ->
  Bin = openagentic_tool_webfetch_runtime:to_bin(Bin0),
  case byte_size(Bin) of
    0 -> Bin;
    _ ->
      case binary:last(Bin) of
        $/ -> binary:part(Bin, 0, byte_size(Bin) - 1);
        _ -> Bin
      end
  end.

first_non_blank([]) -> undefined;
first_non_blank([false | Rest]) -> first_non_blank(Rest);
first_non_blank([undefined | Rest]) -> first_non_blank(Rest);
first_non_blank([null | Rest]) -> first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V = string:trim(openagentic_tool_webfetch_runtime:to_bin(V0)),
  case V of
    <<>> -> first_non_blank(Rest);
    <<"undefined">> -> first_non_blank(Rest);
    <<"false">> -> first_non_blank(Rest);
    _ -> V
  end.

http_request(Method, Url0, Headers0, Body0, Ctx0) ->
  Ctx = openagentic_tool_webfetch_runtime:ensure_map(Ctx0),
  case maps:get(webfetch_http_transport, Ctx, undefined) of
    Fun when is_function(Fun, 4) ->
      Fun(Method, Url0, Headers0, Body0);
    _ ->
      default_http_request(Method, Url0, Headers0, Body0)
  end.

default_http_request(post, Url0, Headers0, Body0) ->
  Url = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  case httpc:request(post, {Url, Headers0, "application/json", Body0}, [{timeout, 60000}], [{body_format, binary}], openagentic_webfetch) of
    {ok, {{_, Status, _}, RespHeaders, RespBody}} -> {ok, {Status, RespHeaders, RespBody}};
    Err -> {error, Err}
  end;
default_http_request(get, Url0, Headers0, _Body0) ->
  Url = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  case httpc:request(get, {Url, Headers0}, [{timeout, 60000}], [{body_format, binary}], openagentic_webfetch) of
    {ok, {{_, Status, _}, RespHeaders, RespBody}} -> {ok, {Status, RespHeaders, RespBody}};
    Err -> {error, Err}
  end;
default_http_request(_Method, _Url0, _Headers0, _Body0) ->
  {error, unsupported_method}.

trim_bin(Bin0) ->
  string:trim(openagentic_tool_webfetch_runtime:to_bin(Bin0)).
