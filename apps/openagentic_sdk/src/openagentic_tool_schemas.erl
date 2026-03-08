-module(openagentic_tool_schemas).

-export([responses_tools/1, responses_tools/2]).

responses_tools(ToolModules) when is_list(ToolModules) ->
  openagentic_tool_schemas_api:responses_tools(ToolModules).

responses_tools(ToolModules, Ctx0) when is_list(ToolModules) ->
  openagentic_tool_schemas_api:responses_tools(ToolModules, Ctx0).
