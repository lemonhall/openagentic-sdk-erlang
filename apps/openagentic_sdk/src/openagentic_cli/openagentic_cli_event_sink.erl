-module(openagentic_cli_event_sink).
-export([event_sink/2,maybe_break_delta/0,remember_tool_name/2,recall_tool_name/1,maybe_forget_tool_name/1]).

event_sink(Stream, Fmt0) ->
  Fmt = openagentic_cli_values:ensure_map(Fmt0),
  Color = openagentic_cli_values:to_bool_default(maps:get(color, Fmt, openagentic_cli_ansi:auto_color()), openagentic_cli_ansi:auto_color()),
  RenderMarkdown = openagentic_cli_values:to_bool_default(maps:get(render_markdown, Fmt, true), true),
  fun (Ev0) ->
    Ev = openagentic_cli_values:ensure_map(Ev0),
    Type = openagentic_cli_values:to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))),
    case Type of
      <<"assistant.delta">> ->
        Delta = openagentic_cli_values:to_bin(maps:get(text_delta, Ev, maps:get(<<"text_delta">>, Ev, <<>>))),
        put(last_was_delta, true),
        io:put_chars(Delta);
      <<"assistant.message">> ->
        LastDelta = get(last_was_delta),
        case {Stream, LastDelta} of
          {true, true} ->
            put(last_was_delta, false),
            io:format("~n", []);
          _ ->
            Txt = openagentic_cli_values:to_bin(maps:get(text, Ev, maps:get(<<"text">>, Ev, <<>>))),
            Txt2 = openagentic_cli_text_format:format_assistant_text(Txt, Color, RenderMarkdown),
            io:format(
              "~ts~n",
              [openagentic_cli_values:to_text(iolist_to_binary([openagentic_cli_ansi:ansi(<<"magenta">>, <<"assistant:">>, Color), <<" ">>, Txt2]))]
            )
        end;
      <<"tool.use">> ->
        maybe_break_delta(),
        Name = openagentic_cli_values:to_bin(maps:get(name, Ev, maps:get(<<"name">>, Ev, <<>>))),
        ToolUseId = openagentic_cli_values:to_bin(maps:get(tool_use_id, Ev, maps:get(<<"tool_use_id">>, Ev, <<>>))),
        Input = openagentic_cli_values:ensure_map(maps:get(input, Ev, maps:get(<<"input">>, Ev, #{}))),
        _ = remember_tool_name(ToolUseId, Name),
        Summary = openagentic_cli_tool_use:tool_use_summary(Name, Input),
        Line = [openagentic_cli_ansi:ansi(<<"cyan">>, <<"tool.use">>, Color), <<" ">>, openagentic_cli_ansi:ansi(<<"cyan">>, Name, Color), openagentic_cli_ansi:format_cli_line(Summary, Color)],
        io:format("~ts~n", [openagentic_cli_values:to_text(iolist_to_binary(Line))]);
      <<"tool.result">> ->
        maybe_break_delta(),
        ToolUseId = openagentic_cli_values:to_bin(maps:get(tool_use_id, Ev, maps:get(<<"tool_use_id">>, Ev, <<>>))),
        ToolName = recall_tool_name(ToolUseId),
        IsError = maps:get(is_error, Ev, maps:get(<<"is_error">>, Ev, false)),
        case IsError of
          true ->
            Et = openagentic_cli_values:to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<"error">>))),
            Em = openagentic_cli_values:to_bin(maps:get(error_message, Ev, maps:get(<<"error_message">>, Ev, <<>>))),
            io:format(
              "~ts~n",
              [openagentic_cli_values:to_text(iolist_to_binary([openagentic_cli_ansi:ansi(<<"red">>, <<"tool.result ERROR">>, Color), <<" ">>, openagentic_cli_ansi:ansi(<<"red">>, Et, Color), <<": ">>, openagentic_cli_ansi:format_cli_line(Em, Color)]))]
            ),
            io:format("~n", []),
            maybe_forget_tool_name(ToolUseId);
          false ->
            Output = maps:get(output, Ev, maps:get(<<"output">>, Ev, undefined)),
            Lines = openagentic_cli_tool_result:tool_result_lines(ToolName, Output),
            io:format("~ts~n", [openagentic_cli_values:to_text(openagentic_cli_ansi:ansi(<<"green">>, <<"tool.result ok">>, Color))]),
            lists:foreach(fun (L0) -> io:format("~ts~n", [openagentic_cli_values:to_text(openagentic_cli_ansi:format_cli_line(L0, Color))]) end, Lines),
            io:format("~n", []),
            maybe_forget_tool_name(ToolUseId)
        end;
      <<"runtime.error">> ->
        maybe_break_delta(),
        Phase = openagentic_cli_values:to_bin(maps:get(phase, Ev, maps:get(<<"phase">>, Ev, <<>>))),
        Et = openagentic_cli_values:to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<>>))),
        io:format(
          "~ts~n~n",
          [openagentic_cli_values:to_text(iolist_to_binary([openagentic_cli_ansi:ansi(<<"red">>, <<"runtime.error">>, Color), <<" ">>, openagentic_cli_ansi:ansi(<<"red">>, Phase, Color), <<" ">>, openagentic_cli_ansi:ansi(<<"red">>, Et, Color)]))]
        );
      <<"result">> ->
        maybe_break_delta(),
        Stop = openagentic_cli_values:to_bin(maps:get(stop_reason, Ev, maps:get(<<"stop_reason">>, Ev, <<>>))),
        io:format(
          "~ts~n",
          [openagentic_cli_values:to_text(iolist_to_binary([openagentic_cli_ansi:ansi(<<"yellow">>, <<"result">>, Color), <<" stop_reason=">>, openagentic_cli_ansi:ansi(<<"yellow">>, Stop, Color)]))]
        );
      _ ->
        ok
    end
  end.

maybe_break_delta() ->
  case get(last_was_delta) of
    true ->
      put(last_was_delta, false),
      io:format("~n", []);
    _ ->
      ok
  end.

remember_tool_name(ToolUseId0, Name0) ->
  ToolUseId = openagentic_cli_values:to_bin(ToolUseId0),
  Name = openagentic_cli_values:to_bin(Name0),
  case byte_size(string:trim(ToolUseId)) > 0 of
    true -> put({tool_name_by_id, ToolUseId}, Name);
    false -> ok
  end,
  ok.

recall_tool_name(ToolUseId0) ->
  ToolUseId = openagentic_cli_values:to_bin(ToolUseId0),
  case get({tool_name_by_id, ToolUseId}) of
    V when is_binary(V) -> V;
    _ -> <<>>
  end.

maybe_forget_tool_name(ToolUseId0) ->
  ToolUseId = openagentic_cli_values:to_bin(ToolUseId0),
  _ = erase({tool_name_by_id, ToolUseId}),
  ok.
