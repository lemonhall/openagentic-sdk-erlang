-module(openagentic_tool_webfetch_extract).

-export([strip_boilerplate/1, select_main_content/1, prune_non_content_blocks/1, extract_first_tag/2]).

strip_boilerplate(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Tags = [
    <<"script">>, <<"style">>, <<"noscript">>, <<"svg">>, <<"canvas">>,
    <<"iframe">>, <<"video">>, <<"audio">>, <<"picture">>, <<"source">>,
    <<"header">>, <<"footer">>, <<"nav">>, <<"aside">>, <<"form">>, <<"button">>
  ],
  Html1 = lists:foldl(fun (Tag, AccHtml) -> openagentic_tool_webfetch_sanitize:remove_blocks(AccHtml, Tag) end, Html, Tags),
  Html2 = remove_role_blocks(Html1),
  Html3 = remove_attr_blocks(Html2, [<<"cookie">>, <<"consent">>, <<"advert">>, <<"ad-">>, <<"ads">>]),
  Html3.

remove_role_blocks(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Pat = <<"<([a-zA-Z0-9]+)[^>]*\\brole\\s*=\\s*\\\"(banner|navigation|contentinfo|complementary)\\\"[^>]*>[\\s\\S]*?</\\1>">>,
  re:replace(Html, Pat, <<>>, [global, caseless, dotall, {return, binary}]).

remove_attr_blocks(Html0, Tokens) ->
  lists:foldl(
    fun (Tok0, Acc0) ->
      Tok = openagentic_tool_webfetch_runtime:to_bin(Tok0),
      Pat =
        iolist_to_binary([
          <<"<([a-zA-Z0-9]+)[^>]*(?:class|id)\\s*=\\s*\\\"[^\\\"]*">>,
          Tok,
          <<"[^\\\"]*\\\"[^>]*>[\\s\\S]*?</\\1>">>
        ]),
      re:replace(Acc0, Pat, <<>>, [global, caseless, dotall, {return, binary}])
    end,
    openagentic_tool_webfetch_runtime:to_bin(Html0),
    Tokens
  ).

select_main_content(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  case extract_first_tag(Html, <<"article">>) of
    {ok, V} -> V;
    _ ->
      case extract_first_tag(Html, <<"main">>) of
        {ok, V2} -> V2;
        _ ->
          case extract_first_tag(Html, <<"body">>) of
            {ok, V3} -> V3;
            _ -> Html
          end
      end
  end.

extract_first_tag(Html0, Tag0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Tag = openagentic_tool_webfetch_runtime:to_list(Tag0),
  Pat = iolist_to_binary([<<"<">>, Tag, <<"\\b[^>]*>[\\s\\S]*?</">>, Tag, <<">">>]),
  case re:run(Html, Pat, [caseless, dotall, {capture, first, binary}]) of
    {match, [M]} -> {ok, M};
    _ -> {error, not_found}
  end.

prune_non_content_blocks(Html0) ->
  remove_attr_blocks(Html0, [
    <<"breadcrumb">>, <<"share">>, <<"social">>, <<"comment">>,
    <<"author">>, <<"byline">>, <<"newsletter">>, <<"subscribe">>, <<"promo">>
  ]).
