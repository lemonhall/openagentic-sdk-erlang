-module(openagentic_cli_tool_use).
-export([tool_use_summary/2]).
tool_use_summary(Name, Input) when Name =:= <<"WebSearch">>; Name =:= <<"WebFetch">>; Name =:= <<"Read">>; Name =:= <<"List">>; Name =:= <<"Glob">>; Name =:= <<"Grep">> ->
  openagentic_cli_tool_use_search_fs:tool_use_summary(Name, Input);
tool_use_summary(Name, Input) when Name =:= <<"Skill">>; Name =:= <<"SlashCommand">>; Name =:= <<"Write">>; Name =:= <<"Edit">>; Name =:= <<"Bash">>; Name =:= <<"NotebookEdit">> ->
  openagentic_cli_tool_use_content:tool_use_summary(Name, Input);
tool_use_summary(Name, Input) ->
  openagentic_cli_tool_use_tasking:tool_use_summary(Name, Input).
