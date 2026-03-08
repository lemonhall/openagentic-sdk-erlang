-module(openagentic_events_tooling).
-export([hook_event/7, tool_output_compacted/2, tool_result/5, tool_use/3]).

hook_event(HookPoint, Name, Matched, DurationMs, Action, ErrorType, ErrorMessage) ->
  Base = #{type => <<"hook.event">>, hook_point => openagentic_events_utils:to_bin(HookPoint), name => openagentic_events_utils:to_bin(Name), matched => Matched},
  Base2 = case DurationMs of undefined -> Base; _ -> Base#{duration_ms => DurationMs} end,
  Base3 = case Action of undefined -> Base2; <<>> -> Base2; "" -> Base2; _ -> Base2#{action => openagentic_events_utils:to_bin(Action)} end,
  Base4 = case ErrorType of undefined -> Base3; <<>> -> Base3; "" -> Base3; _ -> Base3#{error_type => openagentic_events_utils:to_bin(ErrorType)} end,
  case ErrorMessage of undefined -> Base4; <<>> -> Base4; "" -> Base4; _ -> Base4#{error_message => openagentic_events_utils:to_bin(ErrorMessage)} end.

tool_use(ToolUseId, Name, Input) -> #{type => <<"tool.use">>, tool_use_id => openagentic_events_utils:to_bin(ToolUseId), name => openagentic_events_utils:to_bin(Name), input => openagentic_events_utils:ensure_map(Input)}.

tool_result(ToolUseId, Output, IsError, ErrorType, ErrorMessage) ->
  Base = #{type => <<"tool.result">>, tool_use_id => openagentic_events_utils:to_bin(ToolUseId), is_error => IsError},
  Base2 = case Output of undefined -> Base; null -> Base; _ -> Base#{output => Output} end,
  case IsError of true -> Base2#{error_type => openagentic_events_utils:to_bin(ErrorType), error_message => openagentic_events_utils:to_bin(ErrorMessage)}; false -> Base2 end.

tool_output_compacted(ToolUseId0, CompactedTs0) ->
  ToolUseId = openagentic_events_utils:to_bin(ToolUseId0),
  Ts =
    case CompactedTs0 of
      undefined -> undefined;
      null -> undefined;
      T when is_float(T) -> T;
      T when is_integer(T) -> T * 1.0;
      B when is_binary(B) -> case catch binary_to_float(string:trim(B)) of F when is_float(F) -> F; _ -> undefined end;
      _ -> undefined
    end,
  Base = #{type => <<"tool.output_compacted">>, tool_use_id => ToolUseId},
  case Ts of undefined -> Base; _ -> Base#{compacted_ts => Ts} end.
