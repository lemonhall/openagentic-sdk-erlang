-module(openagentic_tool_webfetch_tavily_format).

-export([tavily_text_for_mode/2]).

tavily_text_for_mode(Md0, Mode0) ->
  Md = openagentic_tool_webfetch_sanitize:normalize_markdown(openagentic_tool_webfetch_runtime:to_bin(Md0)),
  Mode = string:lowercase(string:trim(openagentic_tool_webfetch_runtime:to_bin(Mode0))),
  case Mode of
    <<"text">> -> markdown_to_text(Md);
    <<"clean_html">> -> markdown_to_clean_html(Md);
    _ -> Md
  end.

markdown_to_text(Md0) ->
  Md = openagentic_tool_webfetch_sanitize:normalize_markdown(Md0),
  Lines = [markdown_to_text_line(L) || L <- binary:split(Md, <<"\n">>, [global])],
  string:trim(iolist_to_binary(lists:join(<<"\n">>, Lines))).

markdown_to_text_line(Line0) ->
  Line1 = string:trim(openagentic_tool_webfetch_runtime:to_bin(Line0)),
  Line2 = strip_heading_prefix(Line1),
  Line3 =
    case Line2 of
      <<"- ", Rest/binary>> -> Rest;
      <<"* ", Rest/binary>> -> Rest;
      _ -> Line2
    end,
  re:replace(Line3, <<"\[([^\]]+)\]\(([^\)]+)\)">>, <<"\1 (\2)">>, [global, {return, binary}]).

strip_heading_prefix(<<"# ", Rest/binary>>) -> Rest;
strip_heading_prefix(<<"## ", Rest/binary>>) -> Rest;
strip_heading_prefix(<<"### ", Rest/binary>>) -> Rest;
strip_heading_prefix(<<"#### ", Rest/binary>>) -> Rest;
strip_heading_prefix(<<"##### ", Rest/binary>>) -> Rest;
strip_heading_prefix(<<"###### ", Rest/binary>>) -> Rest;
strip_heading_prefix(Line) -> Line.

markdown_to_clean_html(Md0) ->
  Md = openagentic_tool_webfetch_sanitize:normalize_markdown(Md0),
  Blocks = [string:trim(B) || B <- binary:split(Md, <<"\n\n">>, [global]), byte_size(string:trim(B)) > 0],
  HtmlBlocks = [markdown_block_to_html(B) || B <- Blocks],
  iolist_to_binary(lists:join(<<"\n">>, HtmlBlocks)).

markdown_block_to_html(<<"# ", Rest/binary>>) -> heading_html(1, Rest);
markdown_block_to_html(<<"## ", Rest/binary>>) -> heading_html(2, Rest);
markdown_block_to_html(<<"### ", Rest/binary>>) -> heading_html(3, Rest);
markdown_block_to_html(<<"#### ", Rest/binary>>) -> heading_html(4, Rest);
markdown_block_to_html(<<"##### ", Rest/binary>>) -> heading_html(5, Rest);
markdown_block_to_html(<<"###### ", Rest/binary>>) -> heading_html(6, Rest);
markdown_block_to_html(Block0) ->
  Block = html_escape(Block0),
  Inner = binary:replace(Block, <<"\n">>, <<"<br>">>, [global]),
  <<"<p>", Inner/binary, "</p>">>.

heading_html(Level, Text0) ->
  Text = html_escape(Text0),
  Tag = integer_to_binary(Level),
  <<"<h", Tag/binary, ">", Text/binary, "</h", Tag/binary, ">">>.

html_escape(B0) ->
  B1 = binary:replace(openagentic_tool_webfetch_runtime:to_bin(B0), <<"&">>, <<"&amp;">>, [global]),
  B2 = binary:replace(B1, <<"<">>, <<"&lt;">>, [global]),
  B3 = binary:replace(B2, <<">">>, <<"&gt;">>, [global]),
  B4 = binary:replace(B3, <<"\"">>, <<"&quot;">>, [global]),
  binary:replace(B4, <<"'">>, <<"&#39;">>, [global]).
