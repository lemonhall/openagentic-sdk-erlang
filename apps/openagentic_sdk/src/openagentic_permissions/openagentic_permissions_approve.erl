-module(openagentic_permissions_approve).

-export([approve/4]).

approve(Gate0, ToolName0, ToolInput0, Context0) ->
  Gate = openagentic_permissions_utils:ensure_map(Gate0),
  ToolName = openagentic_permissions_utils:to_bin(ToolName0),
  ToolInput = openagentic_permissions_utils:ensure_map(ToolInput0),
  Context = openagentic_permissions_utils:ensure_map(Context0),
  case ToolName of
    <<"AskUserQuestion">> ->
      #{allowed => true};
    _ ->
      Mode = maps:get(mode, Gate, default),
      approve_mode(Mode, Gate, ToolName, ToolInput, Context)
  end.

approve_mode(bypass, _Gate, _ToolName, _ToolInput, _Context) ->
  #{allowed => true};
approve_mode(deny, _Gate, ToolName, _ToolInput, _Context) ->
  #{allowed => false, deny_message => <<"PermissionGate(mode=DENY) denied tool '", ToolName/binary, "'">>};
approve_mode(default, Gate, ToolName, ToolInput, Context) ->
  Safe = openagentic_permissions_policy:safe_tools(),
  case {lists:member(ToolName, Safe), openagentic_permissions_policy:is_workspace_write_tool_allowed(ToolName, ToolInput, Context)} of
    {true, _} ->
      case openagentic_permissions_policy:safe_schema_ok(ToolName, ToolInput) of
        true -> #{allowed => true};
        false -> #{
          allowed => false,
          deny_message => <<"PermissionGate(mode=DEFAULT) schema parse failed for tool '", ToolName/binary, "'">>
        }
      end;
    {false, true} ->
      #{allowed => true};
    {false, false} ->
      approve_mode(prompt, Gate, ToolName, ToolInput, Context)
  end;
approve_mode(prompt, Gate, ToolName, _ToolInput, Context) ->
  Question = #{
    type => <<"user.question">>,
    question_id => openagentic_permissions_utils:question_id(Context),
    prompt => <<"Allow tool ", ToolName/binary, "?">>,
    choices => [<<"yes">>, <<"no">>]
  },
  case maps:get(user_answerer, Gate, undefined) of
    F when is_function(F, 1) ->
      #{allowed => pending, question => Question};
    _ ->
      ModeUpper = openagentic_permissions_utils:mode_upper(maps:get(mode, Gate, prompt)),
      #{
        allowed => false,
        deny_message => <<
          "PermissionGate(mode=", ModeUpper/binary,
          ") requires userAnswerer, but none is configured for tool '",
          ToolName/binary,
          "'"
        >>
      }
  end.
