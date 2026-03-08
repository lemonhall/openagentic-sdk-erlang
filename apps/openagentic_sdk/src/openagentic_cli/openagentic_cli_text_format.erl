-module(openagentic_cli_text_format).
-export([format_assistant_text/3,normalize_newlines/1,highlight_common/2,highlight_urls/1,highlight_paths/1,highlight_quoted_kv/1,highlight_inline_code/1,render_markdown/2,render_markdown_lines/4,render_markdown_line/2,starts_with/2]).

format_assistant_text(Txt0, Color, RenderMarkdown) ->
  Txt1 = openagentic_cli_tool_output_utils:redact_secrets(openagentic_cli_values:to_bin(Txt0)),
  Txt = normalize_newlines(Txt1),
  case RenderMarkdown of
    true -> render_markdown(Txt, Color);
    false -> highlight_common(Txt, Color)
  end.

normalize_newlines(Bin0) ->
  Bin = openagentic_cli_values:to_bin(Bin0),
  openagentic_cli_tool_output_utils:re_replace(Bin, <<"\r\n">>, <<"\n">>).

highlight_common(Bin0, false) ->
  openagentic_cli_values:to_bin(Bin0);
highlight_common(Bin0, true) ->
  Bin = openagentic_cli_values:to_bin(Bin0),
  %% highlight URLs, quoted commands, and common filesystem paths/kv pairs.
  B1 = highlight_quoted_kv(Bin),
  B2 = highlight_urls(B1),
  B3 = highlight_paths(B2),
  B4 = highlight_inline_code(B3),
  B4.

highlight_urls(Bin0) ->
  UrlStyle = openagentic_cli_ansi:ansi_seq(<<"blue_under">>),
  Reset = openagentic_cli_ansi:ansi_reset(),
  %% keep it conservative: stop at whitespace or common closing delimiters
  Pattern = <<"(https?://[^\\s\\)\\]}>\\\"\\']+)">>,
  Replace = iolist_to_binary([UrlStyle, <<"\\1">>, Reset]),
  openagentic_cli_tool_output_utils:re_replace(Bin0, Pattern, Replace).

highlight_paths(Bin0) ->
  Blue = openagentic_cli_ansi:ansi_seq(<<"blue">>),
  Reset = openagentic_cli_ansi:ansi_reset(),
  %% Windows drive paths: E:\foo or e:/foo
  P1 = <<"(?i)([a-z]:[\\\\/][^\\s\\)\\]}>\\\"\\']+)">>,
  R1 = iolist_to_binary([Blue, <<"\\1">>, Reset]),
  B1 = openagentic_cli_tool_output_utils:re_replace(Bin0, P1, R1),
  %% Relative paths: ./foo or .\foo
  P2 = <<"(\\./[^\\s\\)\\]}>\\\"\\']+|\\.\\\\[^\\s\\)\\]}>\\\"\\']+)">>,
  R2 = iolist_to_binary([Blue, <<"\\1">>, Reset]),
  openagentic_cli_tool_output_utils:re_replace(B1, P2, R2).

highlight_quoted_kv(Bin0) ->
  Yellow = openagentic_cli_ansi:ansi_seq(<<"yellow">>),
  Reset = openagentic_cli_ansi:ansi_reset(),
  %% command="...": highlight the inside
  P1 = <<"command=\\\"([^\\\"]+)\\\"">>,
  R1 = iolist_to_binary([<<"command=\\\"">>, Yellow, <<"\\1">>, Reset, <<"\\\"">>]),
  B1 = openagentic_cli_tool_output_utils:re_replace(Bin0, P1, R1),
  %% file_path=/path or workdir=...: highlight value part
  P2 = <<"(?i)\\b(file_path|path|root|workdir|url)=(\\S+)">>,
  R2 = iolist_to_binary([<<"\\1=">>, Yellow, <<"\\2">>, Reset]),
  openagentic_cli_tool_output_utils:re_replace(B1, P2, R2).

highlight_inline_code(Bin0) ->
  Yellow = openagentic_cli_ansi:ansi_seq(<<"yellow">>),
  Reset = openagentic_cli_ansi:ansi_reset(),
  %% inline `code`
  P = <<"`([^`\\n]+)`">>,
  R = iolist_to_binary([Yellow, <<"`\\1`">>, Reset]),
  openagentic_cli_tool_output_utils:re_replace(Bin0, P, R).

render_markdown(Text0, Color) ->
  Text = openagentic_cli_values:to_bin(Text0),
  Lines = binary:split(Text, <<"\n">>, [global]),
  {OutLines, _} = render_markdown_lines(Lines, Color, false, []),
  iolist_to_binary(lists:join(<<"\n">>, lists:reverse(OutLines))).

render_markdown_lines([], _Color, InCode, Acc) ->
  {Acc, InCode};
render_markdown_lines([Line0 | Rest], Color, InCode0, Acc0) ->
  Line = openagentic_cli_values:to_bin(Line0),
  Trim = string:trim(Line),
  case starts_with(Trim, <<"```">>) of
    true ->
      %% show fence dim and toggle code mode
      L2 = iolist_to_binary(openagentic_cli_ansi:ansi(<<"dim">>, Line, Color)),
      render_markdown_lines(Rest, Color, not InCode0, [L2 | Acc0]);
    false when InCode0 =:= true ->
      L2 = iolist_to_binary(openagentic_cli_ansi:ansi(<<"yellow">>, Line, Color)),
      render_markdown_lines(Rest, Color, InCode0, [L2 | Acc0]);
    false ->
      L2 = render_markdown_line(Line, Color),
      render_markdown_lines(Rest, Color, InCode0, [L2 | Acc0])
  end.

render_markdown_line(Line0, Color) ->
  Line = openagentic_cli_values:to_bin(Line0),
  case Line of
    <<$#, _/binary>> ->
      iolist_to_binary(openagentic_cli_ansi:ansi(<<"bold">>, highlight_common(Line, Color), Color));
    <<"- ", Rest/binary>> ->
      iolist_to_binary([openagentic_cli_ansi:ansi(<<"dim">>, <<"-">>, Color), <<" ">>, highlight_common(Rest, Color)]);
    <<"* ", Rest/binary>> ->
      iolist_to_binary([openagentic_cli_ansi:ansi(<<"dim">>, <<"*">>, Color), <<" ">>, highlight_common(Rest, Color)]);
    _ ->
      highlight_common(Line, Color)
  end.

starts_with(Bin, Prefix) when is_binary(Bin), is_binary(Prefix) ->
  Sz = byte_size(Prefix),
  case byte_size(Bin) >= Sz of
    true -> binary:part(Bin, 0, Sz) =:= Prefix;
    false -> false
  end.
