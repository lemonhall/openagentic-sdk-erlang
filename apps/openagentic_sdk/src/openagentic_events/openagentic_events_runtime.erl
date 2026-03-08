-module(openagentic_events_runtime).
-export([provider_event/1, result/2, result/7, runtime_error/2, runtime_error/5]).

provider_event(JsonMap) when is_map(JsonMap) -> #{type => <<"provider.event">>, json => JsonMap}.

result(FinalText0, SessionId0, StopReason0, Usage0, ResponseId0, ProviderMetadata0, Steps0) ->
  Base = #{type => <<"result">>, final_text => openagentic_events_utils:to_bin(FinalText0), session_id => openagentic_events_utils:to_bin(SessionId0)},
  BaseStop = case StopReason0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; SR -> Base#{stop_reason => openagentic_events_utils:to_bin(SR)} end,
  Base2 = case Usage0 of undefined -> BaseStop; null -> BaseStop; U when is_map(U) -> BaseStop#{usage => U}; _ -> BaseStop end,
  Base3 = case ResponseId0 of undefined -> Base2; null -> Base2; <<>> -> Base2; "" -> Base2; Rid -> Base2#{response_id => openagentic_events_utils:to_bin(Rid)} end,
  Base4 = case ProviderMetadata0 of undefined -> Base3; null -> Base3; M when is_map(M) -> Base3#{provider_metadata => M}; _ -> Base3 end,
  case Steps0 of undefined -> Base4; null -> Base4; S when is_integer(S) -> Base4#{steps => S}; _ -> Base4 end.

result(ResponseId, StopReason) -> #{type => <<"result">>, response_id => openagentic_events_utils:to_bin(ResponseId), stop_reason => openagentic_events_utils:to_bin(StopReason)}.

runtime_error(Phase0, ErrorType0, ErrorMessage0, Provider0, ToolUseId0) ->
  Base = #{type => <<"runtime.error">>, phase => openagentic_events_utils:to_bin(Phase0), error_type => openagentic_events_utils:to_bin(ErrorType0)},
  Base2 = case ErrorMessage0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; M -> Base#{error_message => openagentic_events_utils:to_bin(M)} end,
  Base3 = case Provider0 of undefined -> Base2; null -> Base2; <<>> -> Base2; "" -> Base2; P -> Base2#{provider => openagentic_events_utils:to_bin(P)} end,
  case ToolUseId0 of undefined -> Base3; null -> Base3; <<>> -> Base3; "" -> Base3; T -> Base3#{tool_use_id => openagentic_events_utils:to_bin(T)} end.

runtime_error(Message, Raw) -> #{type => <<"runtime.error">>, message => openagentic_events_utils:to_bin(Message), raw => Raw}.
