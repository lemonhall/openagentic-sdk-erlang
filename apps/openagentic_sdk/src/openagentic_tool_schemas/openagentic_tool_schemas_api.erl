-module(openagentic_tool_schemas_api).

-export([responses_tools/1, responses_tools/2]).

responses_tools(ToolModules) when is_list(ToolModules) ->
  responses_tools(ToolModules, #{}).

responses_tools(ToolModules, Ctx0) when is_list(ToolModules) ->
  Ctx = openagentic_tool_schemas_utils:ensure_map(Ctx0),
  lists:map(fun (Mod) -> tool_to_schema(Mod, Ctx) end, ToolModules).

tool_to_schema(Mod, Ctx) ->
  Name = Mod:name(),
  Desc0 = Mod:description(),
  Desc = openagentic_tool_schemas_descriptions:maybe_inject_description(Name, Desc0, Ctx),
  Params = openagentic_tool_schemas_params:tool_params(Mod, Name),
  #{type => <<"function">>, name => Name, description => Desc, parameters => Params}.
