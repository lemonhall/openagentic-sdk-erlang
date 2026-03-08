-module(openagentic_cli_tool_result_fs).
-export([tool_result_lines/2]).

tool_result_lines(<<"List">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  Count = maps:get(count, Output, maps:get(<<"count">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"List path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 200)]),
    iolist_to_binary([<<"count=">>, openagentic_cli_values:to_bin(Count), <<" truncated=">>, openagentic_cli_values:to_bin(Tr)])
  ];
tool_result_lines(<<"Read">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  Total = maps:get(total_lines, Output, maps:get(<<"total_lines">>, Output, undefined)),
  Returned = maps:get(lines_returned, Output, maps:get(<<"lines_returned">>, Output, undefined)),
  Bytes = maps:get(bytes_returned, Output, maps:get(<<"bytes_returned">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Read file_path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 220)]),
    iolist_to_binary([<<"bytes_returned=">>, openagentic_cli_values:to_bin(Bytes), <<" lines_returned=">>, openagentic_cli_values:to_bin(Returned), <<" total_lines=">>, openagentic_cli_values:to_bin(Total), <<" truncated=">>, openagentic_cli_values:to_bin(Tr)])
  ];
tool_result_lines(<<"Glob">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Pattern = maps:get(pattern, Output, maps:get(<<"pattern">>, Output, <<>>)),
  Root = maps:get(root, Output, maps:get(<<"root">>, Output, <<>>)),
  Count = maps:get(count, Output, maps:get(<<"count">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Glob pattern=\"">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Pattern), 140), <<"\" root=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Root), 220)]),
    iolist_to_binary([<<"count=">>, openagentic_cli_values:to_bin(Count), <<" truncated=">>, openagentic_cli_values:to_bin(Tr)])
  ];
tool_result_lines(<<"Grep">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Root = maps:get(root, Output, maps:get(<<"root">>, Output, <<>>)),
  Query = maps:get(query, Output, maps:get(<<"query">>, Output, <<>>)),
  Total = maps:get(total_matches, Output, maps:get(<<"total_matches">>, Output, maps:get(count, Output, maps:get(<<"count">>, Output, undefined)))),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Grep root=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Root), 220)]),
    iolist_to_binary([<<"query=\"">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Query), 120), <<"\" total=">>, openagentic_cli_values:to_bin(Total), <<" truncated=">>, openagentic_cli_values:to_bin(Tr)])
  ];

tool_result_lines(<<"Write">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  Bytes = maps:get(bytes_written, Output, maps:get(<<"bytes_written">>, Output, undefined)),
  [iolist_to_binary([<<"Write file_path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 220), <<" bytes_written=">>, openagentic_cli_values:to_bin(Bytes)])];
tool_result_lines(<<"Edit">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  R = maps:get(replacements, Output, maps:get(<<"replacements">>, Output, undefined)),
  [iolist_to_binary([<<"Edit file_path=">>, openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_values:to_bin(Path), 220), <<" replacements=">>, openagentic_cli_values:to_bin(R)])].
