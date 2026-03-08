-module(openagentic_tool_webfetch_request).

-export([fetch_follow_redirects/4, resolve_url/2]).

fetch_follow_redirects(Url, Headers, Max, Transport) ->
  Chain0 = [Url],
  fetch_follow_redirects2(Url, Headers, Transport, 0, Max, Chain0).

fetch_follow_redirects2(Url, Headers, Transport, I, Max, Chain) when I =< Max ->
  {Status, RespHeaders, Body} = http_get(Url, Headers, Transport),
  case lists:member(Status, [301, 302, 303, 307, 308]) of
    false ->
      {Url, Status, RespHeaders, Body, Chain};
    true ->
      Location = maps:get(<<"location">>, RespHeaders, <<>>),
      case byte_size(string:trim(Location)) > 0 of
        false ->
          {Url, Status, RespHeaders, Body, Chain};
        true ->
          NextUrl = resolve_url(Url, Location),
          ok = openagentic_tool_webfetch_safety:validate_url(NextUrl),
          fetch_follow_redirects2(NextUrl, Headers, Transport, I + 1, Max, Chain ++ [NextUrl])
      end
  end;
fetch_follow_redirects2(_Url, _Headers, _Transport, _I, Max, _Chain) ->
  throw({kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"WebFetch: too many redirects (>">>, integer_to_binary(Max), <<")">>])}).

http_get(Url0, HeadersMap, Transport) when is_function(Transport, 2) ->
  Url = openagentic_tool_webfetch_runtime:to_bin(Url0),
  case Transport(Url, HeadersMap) of
    {ok, {Status, RespHeaders, Body}} ->
      {Status, openagentic_tool_webfetch_api:lower_headers(openagentic_tool_webfetch_runtime:ensure_map(RespHeaders)), openagentic_tool_webfetch_runtime:to_bin(Body)};
    {error, Reason} ->
      throw({http_get_failed, Reason});
    Other ->
      throw({http_get_failed, Other})
  end;
http_get(Url0, HeadersMap, _Transport) ->
  Url = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  Headers = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- maps:to_list(HeadersMap)],
  ReqHeaders = Headers,
  Opts = [{timeout, 60000}, {autoredirect, false}],
  case httpc:request(get, {Url, ReqHeaders}, Opts, [{body_format, binary}], openagentic_webfetch) of
    {ok, {{_, Status, _}, RespHeaders0, Body}} ->
      RespHeaders = maps:from_list([{string:lowercase(openagentic_tool_webfetch_runtime:to_bin(K)), openagentic_tool_webfetch_runtime:to_bin(V)} || {K, V} <- RespHeaders0]),
      {Status, RespHeaders, Body};
    Err ->
      throw({http_get_failed, Err})
  end.

resolve_url(Base0, Location0) ->
  Base = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Base0)),
  Location = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Location0)),
  Res =
    case catch uri_string:resolve(Location, Base) of
      {'EXIT', _} -> Location;
      V -> V
    end,
  openagentic_tool_webfetch_runtime:to_bin(Res).
