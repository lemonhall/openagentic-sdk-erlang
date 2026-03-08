-module(openagentic_cli_tool_result_misc).
-export([tool_result_lines/2]).

tool_result_lines(<<"Skill">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Name = maps:get(name, Output, maps:get(<<"name">>, Output, <<>>)),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  [iolist_to_binary([<<"Skill name=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Name), 80), <<" path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 220)])];
tool_result_lines(<<"SlashCommand">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Name = maps:get(name, Output, maps:get(<<"name">>, Output, <<>>)),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  [iolist_to_binary([<<"SlashCommand name=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Name), 80), <<" path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 220)])];

tool_result_lines(<<"Bash">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Exit = maps:get(exit_code, Output, maps:get(<<"exit_code">>, Output, maps:get(exitCode, Output, maps:get(<<"exitCode">>, Output, undefined)))),
  Killed = maps:get(killed, Output, maps:get(<<"killed">>, Output, undefined)),
  Full = maps:get(full_output_file_path, Output, maps:get(<<"full_output_file_path">>, Output, undefined)),
  [
    iolist_to_binary([<<"Bash exit_code=">>, openagentic_cli_values:to_bin(Exit), <<" killed=">>, openagentic_cli_values:to_bin(Killed)]),
    case Full of null -> <<>>; undefined -> <<>>; <<>> -> <<>>; "" -> <<>>; _ -> iolist_to_binary([<<"full_output_file_path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Full), 260)]) end
  ];
tool_result_lines(<<"NotebookEdit">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Msg = maps:get(message, Output, maps:get(<<"message">>, Output, <<>>)),
  Type = maps:get(edit_type, Output, maps:get(<<"edit_type">>, Output, <<>>)),
  Cell = maps:get(cell_id, Output, maps:get(<<"cell_id">>, Output, <<>>)),
  Total = maps:get(total_cells, Output, maps:get(<<"total_cells">>, Output, undefined)),
  [
    iolist_to_binary([<<"NotebookEdit ">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Msg), 80), <<" edit_type=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Type), 30)]),
    iolist_to_binary([<<"cell_id=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Cell), 80), <<" total_cells=">>, openagentic_cli_values:to_bin(Total)])
  ];
tool_result_lines(<<"lsp">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Title = maps:get(title, Output, maps:get(<<"title">>, Output, <<>>)),
  [iolist_to_binary([<<"lsp ">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Title), 260)])];
tool_result_lines(<<"TodoWrite">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Stats = openagentic_cli_values:ensure_map(maps:get(stats, Output, maps:get(<<"stats">>, Output, #{}))),
  Total = maps:get(total, Stats, maps:get(<<"total">>, Stats, undefined)),
  IP = maps:get(in_progress, Stats, maps:get(<<"in_progress">>, Stats, undefined)),
  P = maps:get(pending, Stats, maps:get(<<"pending">>, Stats, undefined)),
  C = maps:get(completed, Stats, maps:get(<<"completed">>, Stats, undefined)),
  X = maps:get(cancelled, Stats, maps:get(<<"cancelled">>, Stats, undefined)),
  [iolist_to_binary([<<"TodoWrite total=">>, openagentic_cli_values:to_bin(Total), <<" pending=">>, openagentic_cli_values:to_bin(P), <<" in_progress=">>, openagentic_cli_values:to_bin(IP), <<" completed=">>, openagentic_cli_values:to_bin(C), <<" cancelled=">>, openagentic_cli_values:to_bin(X)])];
tool_result_lines(_, _Output) ->
  [].
