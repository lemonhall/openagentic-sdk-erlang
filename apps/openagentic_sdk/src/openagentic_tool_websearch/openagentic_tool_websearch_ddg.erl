-module(openagentic_tool_websearch_ddg).

-export([ddg_out/5]).

ddg_out(Query, MaxResults, Allowed, Blocked, Ctx) ->
  Url = <<"https://html.duckduckgo.com/html/?q=", (openagentic_tool_websearch_text:urlencode(Query))/binary>>,
  Headers = [{"user-agent", "openagentic-sdk-erlang/0.1"}, {"accept", "text/html,application/xhtml+xml"}],
  case openagentic_tool_websearch_runtime:http_request(get, Url, Headers, <<>>, Ctx) of
    {ok, {Status, _RespHeaders, Body}} when Status >= 400 ->
      Raw = openagentic_tool_websearch_utils:to_bin_safe_utf8(Body),
      Msg0 = iolist_to_binary([<<"HTTP ">>, integer_to_binary(Status), <<" from ">>, Url, <<": ">>, Raw]),
      {error, {kotlin_error, <<"RuntimeException">>, openagentic_tool_websearch_utils:trim_bin(Msg0)}};
    {ok, {_Status, _RespHeaders, Body}} ->
      Raw = openagentic_tool_websearch_utils:to_bin_safe_utf8(Body),
      Results =
        case byte_size(Raw) > 0 of
          true -> ddg_parse_results(Raw, MaxResults, Allowed, Blocked);
          false -> []
        end,
      {ok, #{query => Query, results => Results, total_results => length(Results)}};
    {error, Reason} ->
      {error, {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"HTTP request failed: ">>, openagentic_tool_websearch_utils:to_bin(Reason)])}}
  end.

ddg_parse_results(Html, MaxResults, Allowed, Blocked) ->
  Pattern = <<"<a[^>]*class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>">>,
  Opts = [global, caseless, {capture, [1, 2], binary}],
  case re:run(Html, Pattern, Opts) of
    nomatch -> [];
    {match, Captures} -> lists:reverse(take_ddg(Captures, MaxResults, Allowed, Blocked, []))
  end.

take_ddg([], _Max, _Allowed, _Blocked, Acc) -> Acc;
take_ddg(_Caps, Max, _Allowed, _Blocked, Acc) when length(Acc) >= Max -> Acc;
take_ddg([[Href0, TitleHtml0] | Rest], Max, Allowed, Blocked, Acc) ->
  Href = openagentic_tool_websearch_text:html_unescape(Href0),
  Url = decode_ddg_redirect(Href),
  case {byte_size(string:trim(Url)), openagentic_tool_websearch_domain:domain_allowed(Url, Allowed, Blocked)} of
    {0, _} -> take_ddg(Rest, Max, Allowed, Blocked, Acc);
    {_, false} -> take_ddg(Rest, Max, Allowed, Blocked, Acc);
    _ ->
      Title = string:trim(openagentic_tool_websearch_text:tag_strip(openagentic_tool_websearch_text:html_unescape(TitleHtml0))),
      Obj = #{title => Title, url => Url, content => null, source => <<"duckduckgo">>},
      take_ddg(Rest, Max, Allowed, Blocked, [Obj | Acc])
  end;
take_ddg([_ | Rest], Max, Allowed, Blocked, Acc) ->
  take_ddg(Rest, Max, Allowed, Blocked, Acc).

decode_ddg_redirect(Href0) ->
  Href = string:trim(openagentic_tool_websearch_utils:to_bin(Href0)),
  case byte_size(Href) of
    0 -> Href;
    _ ->
      try
        Parsed = uri_string:parse(binary_to_list(Href)),
        case maps:get(query, Parsed, undefined) of
          undefined -> Href;
          QueryString ->
            Params = uri_string:dissect_query(QueryString),
            case lists:keyfind("uddg", 1, Params) of
              false -> Href;
              {"uddg", Url} -> openagentic_tool_websearch_utils:to_bin(uri_string:percent_decode(Url))
            end
        end
      catch
        _:_ -> Href
      end
  end.
