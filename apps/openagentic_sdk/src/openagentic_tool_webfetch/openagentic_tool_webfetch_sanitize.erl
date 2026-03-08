-module(openagentic_tool_webfetch_sanitize).

-export([sanitize_to_text/2, sanitize_to_clean_html/2, sanitize_to_markdown/2, extract_title/1, to_bin_safe_utf8/1, clamp/3, ends_with/2, normalize_markdown/1, remove_blocks/2, tag_strip/1]).

sanitize_to_text(Raw0, _BaseUrl) ->
  Raw = openagentic_tool_webfetch_extract:strip_boilerplate(Raw0),
  string:trim(openagentic_tool_webfetch_markdown:html_unescape(tag_strip(Raw))).

sanitize_to_clean_html(Raw0, BaseUrl0) ->
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Raw = openagentic_tool_webfetch_extract:strip_boilerplate(Raw0),
  Content0 = openagentic_tool_webfetch_extract:select_main_content(Raw),
  Content1 = openagentic_tool_webfetch_extract:prune_non_content_blocks(Content0),
  Html0 = openagentic_tool_webfetch_tags:sanitize_allowlist(Content1, BaseUrl),
  Html1 = openagentic_tool_webfetch_markdown:prune_empty_nodes(Html0),
  Html2 = openagentic_tool_webfetch_markdown:format_block_separators(Html1),
  string:trim(Html2).

sanitize_to_markdown(Raw0, BaseUrl0) ->
  Html = sanitize_to_clean_html(Raw0, BaseUrl0),
  Md0 = openagentic_tool_webfetch_markdown:html_to_markdown(Html, BaseUrl0),
  normalize_markdown(Md0).

remove_blocks(Html0, Tag0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Tag = openagentic_tool_webfetch_runtime:to_bin(Tag0),
  Pat = iolist_to_binary([<<"<">>, Tag, <<"[\\s\\S]*?</">>, Tag, <<">">>]),
  re:replace(Html, Pat, <<>>, [global, caseless, {return, binary}]).

tag_strip(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  re:replace(Html, <<"<.*?>">>, <<>>, [global, {return, binary}]).

extract_title(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  case re:run(Html, <<"<title[^>]*>([\\s\\S]*?)</title>">>, [caseless, {capture, [1], binary}]) of
    {match, [T]} -> string:trim(tag_strip(T));
    _ -> <<>>
  end.

normalize_markdown(Md0) ->
  Md1 = binary:replace(openagentic_tool_webfetch_runtime:to_bin(Md0), <<"\r\n">>, <<"\n">>, [global]),
  Md2 = binary:replace(Md1, <<"\r">>, <<"\n">>, [global]),
  Lines = [string:trim(L, trailing) || L <- binary:split(Md2, <<"\n">>, [global])],
  Md3 = iolist_to_binary(lists:join(<<"\n">>, Lines)),
  Md4 = re:replace(Md3, <<"\n{3,}">>, <<"\n\n">>, [global, {return, binary}]),
  string:trim(Md4).

to_bin_safe_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end.

clamp(I, Min, Max) when is_integer(I) ->
  erlang:max(Min, erlang:min(Max, I));
clamp(_, Min, _Max) ->
  Min.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.
