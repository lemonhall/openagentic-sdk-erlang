-module(openagentic_tool_webfetch_anchors).

-export([sanitize_anchor_open_tags/2, match_span/3, extract_attr/2, resolve_url_bin/2]).

sanitize_anchor_open_tags(Html0, BaseUrl0) ->
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Pat = <<"<a\\b[^>]*>">>,
  sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, 0, []).

sanitize_anchor_open_tags_loop(Html, _BaseUrl, _Pat, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, Pos0, AccRev) ->
  case re:run(Html, Pat, [caseless, {capture, first, binary}, {offset, Pos0}]) of
    {match, [Tag]} ->
      {Start, Len} = match_span(Html, Pat, Pos0),
      PrefixLen = Start - Pos0,
      Prefix = binary:part(Html, Pos0, PrefixLen),
      Tag2 = sanitize_one_anchor_tag(Tag, BaseUrl),
      NewPos = Start + Len,
      sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, NewPos, [Tag2, Prefix | AccRev]);
    _ ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]))
  end.

match_span(Html, Pat, Pos0) ->
  {match, [{Start, Len}]} = re:run(Html, Pat, [caseless, {capture, first, index}, {offset, Pos0}]),
  {Start, Len}.

sanitize_one_anchor_tag(Tag0, BaseUrl0) ->
  Tag = openagentic_tool_webfetch_runtime:to_bin(Tag0),
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Href0 = extract_attr(Tag, <<"href">>),
  Title0 = extract_attr(Tag, <<"title">>),
  Href =
    case Href0 of
      undefined -> undefined;
      <<>> -> undefined;
      HrefVal -> resolve_url_bin(BaseUrl, HrefVal)
    end,
  Title =
    case Title0 of
      undefined -> undefined;
      <<>> -> undefined;
      TitleVal -> TitleVal
    end,
  build_anchor_tag(Href, Title).

build_anchor_tag(undefined, undefined) ->
  <<"<a>">>;
build_anchor_tag(Href, undefined) ->
  iolist_to_binary([<<"<a href=\"">>, Href, <<"\">">>]);
build_anchor_tag(undefined, Title) ->
  iolist_to_binary([<<"<a title=\"">>, escape_attr(Title), <<"\">">>]);
build_anchor_tag(Href, Title) ->
  iolist_to_binary([<<"<a href=\"">>, Href, <<"\" title=\"">>, escape_attr(Title), <<"\">">>]).

escape_attr(Bin0) ->
  Bin = openagentic_tool_webfetch_runtime:to_bin(Bin0),
  Bin1 = binary:replace(Bin, <<"&">>, <<"&amp;">>, [global]),
  Bin2 = binary:replace(Bin1, <<"\"">>, <<"&quot;">>, [global]),
  Bin2.

extract_attr(Tag0, Attr0) ->
  Tag = openagentic_tool_webfetch_runtime:to_bin(Tag0),
  Attr = openagentic_tool_webfetch_runtime:to_list(Attr0),
  Pat =
    iolist_to_binary([
      <<"\\b">>, Attr, <<"\\s*=\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([^\\s>]+))">>
    ]),
  case re:run(Tag, Pat, [caseless, dotall, {capture, [1, 2, 3], binary}]) of
    {match, [V1, V2, V3]} ->
      first_non_empty_bin([V1, V2, V3]);
    _ ->
      undefined
  end.

first_non_empty_bin([]) -> undefined;
first_non_empty_bin([H | T]) ->
  case H of
    undefined -> first_non_empty_bin(T);
    <<>> -> first_non_empty_bin(T);
    _ -> H
  end.

resolve_url_bin(Base0, Rel0) ->
  Base = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Base0)),
  Rel = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Rel0)),
  try
    openagentic_tool_webfetch_runtime:to_bin(uri_string:resolve(Rel, Base))
  catch
    _:_ ->
      openagentic_tool_webfetch_runtime:to_bin(Rel0)
  end.
