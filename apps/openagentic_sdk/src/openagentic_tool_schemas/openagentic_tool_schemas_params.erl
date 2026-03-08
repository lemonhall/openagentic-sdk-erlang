-module(openagentic_tool_schemas_params).

-export([tool_params/2]).

tool_params(Mod, Name) ->
  case openagentic_tool_schemas_params_interactive:tool_params(Mod, Name) of
    undefined ->
      case openagentic_tool_schemas_params_fs:tool_params(Mod, Name) of
        undefined ->
          case openagentic_tool_schemas_params_web:tool_params(Mod, Name) of
            undefined -> openagentic_tool_schemas_params_misc:tool_params(Mod, Name);
            Schema -> Schema
          end;
        Schema -> Schema
      end;
    Schema -> Schema
  end.
