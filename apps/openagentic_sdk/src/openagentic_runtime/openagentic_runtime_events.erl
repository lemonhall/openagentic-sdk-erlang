-module(openagentic_runtime_events).
-export([append_event/2,maybe_emit_event/2,emit_transient_event/2,append_hook_events/2,finish_tool_success/5]).

append_event(State0, Event0) ->
  Root = maps:get(root, State0),
  SessionId = maps:get(session_id, State0),
  {ok, Stored} = openagentic_session_store:append_event(Root, SessionId, Event0),
  _ = maybe_emit_event(State0, Stored),
  Events0 = maps:get(events, State0, []),
  State0#{events := Events0 ++ [Stored]}.

maybe_emit_event(State0, Event) ->
  case maps:get(event_sink, State0, undefined) of
    F when is_function(F, 1) ->
      try
        F(Event)
      catch
        _:_ -> ok
      end;
    _ -> ok
  end.

emit_transient_event(State0, Event) ->
  %% Transient events are not persisted and do not affect session history.
  _ = maybe_emit_event(State0, Event),
  ok.

append_hook_events(State0, Events0) ->
  Events = openagentic_runtime_utils:ensure_list(Events0),
  lists:foldl(fun (E, Acc) -> append_event(Acc, E) end, State0, Events).

finish_tool_success(ToolUseId0, ToolName0, Out0, HookCtx0, State0) ->
  ToolUseId = openagentic_runtime_utils:to_bin(ToolUseId0),
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  HookCtx = openagentic_runtime_utils:ensure_map(HookCtx0),
  HookEngine = maps:get(hook_engine, State0, #{}),
  Post = openagentic_hook_engine:run_post_tool_use(HookEngine, ToolName, Out0, HookCtx),
  State1 = append_hook_events(State0, maps:get(events, Post, [])),
  case maps:get(decision, Post, undefined) of
    D when is_map(D) ->
      case maps:get(block, D, false) of
        true ->
          Reason = maps:get(block_reason, D, <<"blocked by hook">>),
          append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"HookBlocked">>, Reason));
        false ->
          Out1 = maps:get(output, Post, Out0),
          Out2 = openagentic_runtime_artifacts:maybe_externalize_tool_output(ToolUseId, ToolName, Out1, State1),
          append_event(State1, openagentic_events:tool_result(ToolUseId, Out2, false, <<>>, <<>>))
      end;
    _ ->
      Out1 = maps:get(output, Post, Out0),
      Out2 = openagentic_runtime_artifacts:maybe_externalize_tool_output(ToolUseId, ToolName, Out1, State1),
      append_event(State1, openagentic_events:tool_result(ToolUseId, Out2, false, <<>>, <<>>))
  end.
