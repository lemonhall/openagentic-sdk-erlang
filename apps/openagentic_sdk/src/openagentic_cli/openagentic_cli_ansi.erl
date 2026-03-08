-module(openagentic_cli_ansi).
-export([auto_color/0,ansi_reset/0,ansi_seq/1,ansi/3,format_cli_line/2]).

auto_color() ->
  %% Follow https://no-color.org/ : if NO_COLOR is set (any value), disable ANSI.
  case os:getenv("NO_COLOR") of
    false ->
      case os:getenv("OPENAGENTIC_NO_COLOR") of
        false ->
          case os:getenv("TERM") of
            "dumb" -> false;
            _ -> true
          end;
        _ ->
          false
      end;
    _ ->
      false
  end.

ansi_reset() -> <<"\033[0m">>.

ansi_seq(<<"red">>) -> <<"\033[31m">>;
ansi_seq(<<"green">>) -> <<"\033[32m">>;
ansi_seq(<<"yellow">>) -> <<"\033[33m">>;
ansi_seq(<<"blue">>) -> <<"\033[34m">>;
ansi_seq(<<"magenta">>) -> <<"\033[35m">>;
ansi_seq(<<"cyan">>) -> <<"\033[36m">>;
ansi_seq(<<"dim">>) -> <<"\033[2m">>;
ansi_seq(<<"bold">>) -> <<"\033[1m">>;
ansi_seq(<<"underline">>) -> <<"\033[4m">>;
ansi_seq(<<"blue_under">>) -> <<"\033[34m\033[4m">>;
ansi_seq(_) -> <<>>.

ansi(Style0, Text0, Enabled) ->
  case Enabled of
    true ->
      Style = openagentic_cli_values:to_bin(Style0),
      Text = openagentic_cli_values:to_bin(Text0),
      [ansi_seq(Style), Text, ansi_reset()];
    false ->
      openagentic_cli_values:to_bin(Text0)
  end.

format_cli_line(Line0, Color) ->
  Bin0 = openagentic_cli_tool_output_utils:redact_secrets(openagentic_cli_values:to_bin(Line0)),
  Bin = openagentic_cli_text_format:normalize_newlines(Bin0),
  openagentic_cli_text_format:highlight_common(Bin, Color).
