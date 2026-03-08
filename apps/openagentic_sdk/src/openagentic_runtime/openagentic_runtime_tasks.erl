-module(openagentic_runtime_tasks).
-export([handle_task/5]).

handle_task(ToolUseId, ToolName0, ToolInput0, HookCtx, State0) ->
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  ToolInput = openagentic_runtime_utils:ensure_map(ToolInput0),
  Agent = string:trim(openagentic_runtime_utils:to_bin(maps:get(<<"agent">>, ToolInput, maps:get(agent, ToolInput, <<>>)))),
  Prompt = string:trim(openagentic_runtime_utils:to_bin(maps:get(<<"prompt">>, ToolInput, maps:get(prompt, ToolInput, <<>>)))),
  case {byte_size(Agent) > 0, byte_size(Prompt) > 0} of
    {false, _} ->
      openagentic_runtime_events:append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidTaskInput">>,
          <<"Task: 'agent' and 'prompt' must be non-empty strings">>
        )
      );
    {_, false} ->
      openagentic_runtime_events:append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidTaskInput">>,
          <<"Task: 'agent' and 'prompt' must be non-empty strings">>
        )
      );
    {true, true} ->
      case maps:get(task_runner, State0, undefined) of
        F when is_function(F, 3) ->
          SessionId = maps:get(session_id, State0, <<>>),
          Emit = maps:get(task_progress_emitter, State0, undefined),
          ToolCtx =
            case Emit of
              Ef when is_function(Ef, 1) ->
                #{session_id => SessionId, tool_use_id => ToolUseId, emit_progress => Ef, time_context => maps:get(time_context, State0, undefined)};
              _ ->
                #{session_id => SessionId, tool_use_id => ToolUseId, time_context => maps:get(time_context, State0, undefined)}
            end,
          try
            Out = F(Agent, Prompt, ToolCtx),
            openagentic_runtime_events:finish_tool_success(ToolUseId, ToolName, Out, HookCtx, State0)
          catch
            C:R ->
              openagentic_runtime_events:append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"TaskError">>, openagentic_runtime_utils:to_bin({C, R})))
          end;
        _ ->
          openagentic_runtime_events:append_event(
            State0,
            openagentic_events:tool_result(
              ToolUseId,
              undefined,
              true,
              <<"NoTaskRunner">>,
              <<"Task: no taskRunner is configured">>
            )
          )
      end
  end.
