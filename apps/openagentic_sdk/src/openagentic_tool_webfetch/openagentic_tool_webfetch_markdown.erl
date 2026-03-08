-module(openagentic_tool_webfetch_markdown).

-export([prune_empty_nodes/1, format_block_separators/1, html_to_markdown/2, html_unescape/1]).

prune_empty_nodes(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Tags = [<<"div">>, <<"span">>, <<"p">>, <<"section">>, <<"article">>, <<"main">>, <<"blockquote">>,
          <<"ul">>, <<"ol">>, <<"li">>, <<"table">>, <<"thead">>, <<"tbody">>, <<"tr">>, <<"td">>, <<"th">>],
  prune_empty_nodes_passes(Html, Tags, 0, 10).

prune_empty_nodes_passes(Html, _Tags, Pass, MaxPasses) when Pass >= MaxPasses ->
  Html;
prune_empty_nodes_passes(Html0, Tags, Pass, MaxPasses) ->
  Html = lists:foldl(
    fun (T0, Acc0) ->
      T = openagentic_tool_webfetch_runtime:to_list(T0),
      Pat = iolist_to_binary([<<"<">>, T, <<">\\s*</">>, T, <<">">>]),
      re:replace(Acc0, Pat, <<>>, [global, caseless, dotall, {return, binary}])
    end,
    Html0,
    Tags
  ),
  case Html =:= Html0 of
    true -> Html;
    false -> prune_empty_nodes_passes(Html, Tags, Pass + 1, MaxPasses)
  end.

format_block_separators(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Pat = <<">\\s*(?=<(h[1-6]|p|ul|ol|li|table|thead|tbody|tr|td|th|pre|blockquote)\\b)">>,
  re:replace(Html, Pat, <<">\n">>, [global, caseless, {return, binary}]).

html_to_markdown(Html0, BaseUrl0) ->
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  S1 = convert_heading(Html, 1),
  S2 = convert_heading(S1, 2),
  S3 = convert_heading(S2, 3),
  S4 = convert_heading(S3, 4),
  S5 = convert_heading(S4, 5),
  S6 = convert_heading(S5, 6),
  S7 = convert_links_md(S6, BaseUrl),
  S8 = re:replace(S7, <<"<br\\s*/?>">>, <<"\n">>, [global, caseless, {return, binary}]),
  S9 = re:replace(S8, <<"</p>">>, <<"\n\n">>, [global, caseless, {return, binary}]),
  S10 = re:replace(S9, <<"<p>">>, <<>>, [global, caseless, {return, binary}]),
  S11 = re:replace(S10, <<"<li>">>, <<"- ">>, [global, caseless, {return, binary}]),
  S12 = re:replace(S11, <<"</li>">>, <<"\n">>, [global, caseless, {return, binary}]),
  S13 = re:replace(S12, <<"</?(ul|ol)>">>, <<"\n">>, [global, caseless, {return, binary}]),
  Text = html_unescape(openagentic_tool_webfetch_sanitize:tag_strip(S13)),
  Text.

convert_heading(Html0, N) ->
  Tag = iolist_to_binary([<<"h">>, integer_to_binary(N)]),
  Pat = iolist_to_binary([<<"<">>, Tag, <<">([\\s\\S]*?)</">>, Tag, <<">">>]),
  Prefix = lists:duplicate(N, $#),
  Repl = iolist_to_binary([Prefix, <<" \\1\n\n">>]),
  re:replace(openagentic_tool_webfetch_runtime:to_bin(Html0), Pat, Repl, [global, caseless, dotall, {return, binary}]).

convert_links_md(Html0, BaseUrl0) ->
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Pat = <<"<a\\b[^>]*>([\\s\\S]*?)</a>">>,
  convert_links_md_loop(Html, BaseUrl, Pat, 0, []).

convert_links_md_loop(Html, _BaseUrl, _Pat, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
convert_links_md_loop(Html, BaseUrl, Pat, Pos0, AccRev) ->
  case re:run(Html, Pat, [caseless, dotall, {capture, [0, 1], binary}, {offset, Pos0}]) of
    {match, [Full, Inner]} ->
      {Start, Len} = openagentic_tool_webfetch_anchors:match_span(Html, Pat, Pos0),
      Prefix = binary:part(Html, Pos0, Start - Pos0),
      Href0 = openagentic_tool_webfetch_anchors:extract_attr(Full, <<"href">>),
      Href =
        case Href0 of
          undefined -> <<>>;
          <<>> -> <<>>;
          V -> openagentic_tool_webfetch_anchors:resolve_url_bin(BaseUrl, V)
        end,
      Text = string:trim(html_unescape(openagentic_tool_webfetch_sanitize:tag_strip(Inner))),
      Md =
        case {byte_size(Text) > 0, byte_size(Href) > 0} of
          {true, true} -> iolist_to_binary([<<"[">>, Text, <<"](">>, Href, <<")">>]);
          {true, false} -> Text;
          _ -> <<>>
        end,
      NewPos = Start + Len,
      convert_links_md_loop(Html, BaseUrl, Pat, NewPos, [Md, Prefix | AccRev]);
    _ ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]))
  end.

html_unescape(S0) ->
  S1 = binary:replace(openagentic_tool_webfetch_runtime:to_bin(S0), <<"&amp;">>, <<"&">>, [global]),
  S2 = binary:replace(S1, <<"&lt;">>, <<"<">>, [global]),
  S3 = binary:replace(S2, <<"&gt;">>, <<">">>, [global]),
  S4 = binary:replace(S3, <<"&quot;">>, <<"\"">>, [global]),
  binary:replace(S4, <<"&#39;">>, <<"'">>, [global]).
