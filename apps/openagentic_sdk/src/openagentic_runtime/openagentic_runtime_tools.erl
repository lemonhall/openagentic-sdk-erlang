-module(openagentic_runtime_tools).
-export([run_one_tool_call/2,run_one_tool_call_allowed/5,await_permission_answer/3,run_tool/5]).

run_one_tool_call(ToolCall0, State0) ->
  ToolCall = openagentic_runtime_utils:ensure_map(ToolCall0),
  ToolUseId = maps:get(tool_use_id, ToolCall, maps:get(toolUseId, ToolCall, <<>>)),
  ToolName0 = maps:get(name, ToolCall, <<>>),
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  ToolInput0 = openagentic_runtime_utils:ensure_map(maps:get(arguments, ToolCall, #{})),

  HookCtx = #{session_id => maps:get(session_id, State0), tool_use_id => ToolUseId},
  HookEngine = maps:get(hook_engine, State0, #{}),
  Pre = openagentic_hook_engine:run_pre_tool_use(HookEngine, ToolName, ToolInput0, HookCtx),
  StateH = openagentic_runtime_events:append_hook_events(State0, maps:get(events, Pre, [])),
  ToolInput1 = openagentic_runtime_utils:ensure_map(maps:get(input, Pre, ToolInput0)),

  UseEv = openagentic_events:tool_use(ToolUseId, ToolName, ToolInput1),
  State1 = openagentic_runtime_events:append_event(StateH, UseEv),

  case maps:get(decision, Pre, undefined) of
    D when is_map(D) ->
      case maps:get(block, D, false) of
        true ->
          Reason = maps:get(block_reason, D, <<"blocked by hook">>),
          openagentic_runtime_events:append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"HookBlocked">>, Reason));
        false ->
          run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1)
      end;
    _ ->
      run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1)
  end.

run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1) ->
  AllowedTools = maps:get(allowed_tools, State1, undefined),
  case openagentic_runtime_options:is_tool_allowed(AllowedTools, ToolName) of
    false ->
      Msg = iolist_to_binary([<<"Tool '">>, ToolName, <<"' is not allowed">>]),
      openagentic_runtime_events:append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"ToolNotAllowed">>, Msg));
    true ->
      Gate = maps:get(permission_gate, State1),
      Ctx =
        #{
          session_id => maps:get(session_id, State1),
          tool_use_id => ToolUseId,
          workspace_dir => maps:get(workspace_dir, State1, undefined)
        },
      Approval = openagentic_permissions:approve(Gate, ToolName, ToolInput1, Ctx),
      State2 =
        case maps:get(question, Approval, undefined) of
          undefined -> State1;
          Q -> openagentic_runtime_events:append_event(State1, Q)
        end,
      case maps:get(allowed, Approval, false) of
        pending ->
          %% Web HITL needs the question appended BEFORE blocking for an answer.
          Question = maps:get(question, Approval, #{}),
          Approval2 = await_permission_answer(Gate, ToolName, Question),
          case maps:get(allowed, Approval2, false) of
            false ->
              Deny = maps:get(deny_message, Approval2, <<"tool use not approved">>),
              openagentic_runtime_events:append_event(State2, openagentic_events:tool_result(ToolUseId, undefined, true, <<"PermissionDenied">>, Deny));
            true ->
              ToolInput = maps:get(updated_input, Approval, maps:get(updatedInput, Approval, ToolInput1)),
              case ToolName of
                <<"AskUserQuestion">> ->
                  openagentic_runtime_questions:handle_ask_user_question(ToolUseId, ToolName, ToolInput, HookCtx, State2);
                <<"Task">> ->
                  openagentic_runtime_tasks:handle_task(ToolUseId, ToolName, ToolInput, HookCtx, State2);
                _ ->
                  run_tool(ToolUseId, ToolName, ToolInput, HookCtx, State2)
              end
          end;
        false ->
          Deny = maps:get(deny_message, Approval, <<"tool use not approved">>),
          openagentic_runtime_events:append_event(State2, openagentic_events:tool_result(ToolUseId, undefined, true, <<"PermissionDenied">>, Deny));
        true ->
          ToolInput = maps:get(updated_input, Approval, maps:get(updatedInput, Approval, ToolInput1)),
          case ToolName of
            <<"AskUserQuestion">> ->
              openagentic_runtime_questions:handle_ask_user_question(ToolUseId, ToolName, ToolInput, HookCtx, State2);
            <<"Task">> ->
              openagentic_runtime_tasks:handle_task(ToolUseId, ToolName, ToolInput, HookCtx, State2);
            _ ->
              run_tool(ToolUseId, ToolName, ToolInput, HookCtx, State2)
          end
      end
  end
  .

await_permission_answer(Gate0, ToolName0, Question0) ->
  Gate = openagentic_runtime_utils:ensure_map(Gate0),
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  Question = openagentic_runtime_utils:ensure_map(Question0),
  case maps:get(user_answerer, Gate, undefined) of
    F when is_function(F, 1) ->
      Answer = F(Question),
      openagentic_permissions:finalize_prompt(ToolName, Question, Answer);
    _ ->
      %% Should be unreachable: prompt mode without userAnswerer is denied earlier.
      #{
        allowed => false,
        deny_message => <<"PermissionGate(mode=PROMPT) requires userAnswerer">>,
        question => Question
      }
  end.

run_tool(ToolUseId, ToolName0, ToolInput0, HookCtx, State0) ->
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  ToolInput = openagentic_runtime_utils:ensure_map(ToolInput0),
  Registry = maps:get(registry, State0),
  ToolCtx =
    #{
      user_answerer => maps:get(user_answerer, State0, undefined),
      session_id => maps:get(session_id, State0, <<>>),
      tool_use_id => ToolUseId,
      task_runner => maps:get(task_runner, State0, undefined)
    },
  ProjectDir = maps:get(project_dir, State0, maps:get(projectDir, State0, ".")),
  WorkspaceDir = maps:get(workspace_dir, State0, undefined),
  ToolCtx2 = ToolCtx#{project_dir => ProjectDir, workspace_dir => WorkspaceDir},

  case openagentic_tool_registry:get(Registry, ToolName) of
    {ok, Mod} ->
      case Mod:run(ToolInput, ToolCtx2) of
        {ok, Out} ->
          openagentic_runtime_events:finish_tool_success(ToolUseId, ToolName, Out, HookCtx, State0);
        {error, {kotlin_error, ErrorType, ErrorMessage}} ->
          openagentic_runtime_events:append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, ErrorType, ErrorMessage));
        {error, {exception, ErrorType, ErrorMessage}} ->
          openagentic_runtime_events:append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, ErrorType, ErrorMessage));
        {error, Reason} ->
          openagentic_runtime_events:append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"ToolError">>, openagentic_runtime_utils:to_bin(Reason)))
      end;
    {error, not_found} ->
      openagentic_runtime_events:append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"UnknownTool">>, <<"unknown tool">>))
  end.
