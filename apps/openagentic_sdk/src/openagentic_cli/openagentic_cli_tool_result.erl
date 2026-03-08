-module(openagentic_cli_tool_result).
-export([tool_result_lines/2]).
tool_result_lines(Name, Output) when Name =:= <<"WebSearch">>; Name =:= <<"WebFetch">> ->
  openagentic_cli_tool_result_web:tool_result_lines(Name, Output);
tool_result_lines(Name, Output) when Name =:= <<"List">>; Name =:= <<"Read">>; Name =:= <<"Glob">>; Name =:= <<"Grep">>; Name =:= <<"Write">>; Name =:= <<"Edit">> ->
  openagentic_cli_tool_result_fs:tool_result_lines(Name, Output);
tool_result_lines(Name, Output) ->
  openagentic_cli_tool_result_misc:tool_result_lines(Name, Output).
