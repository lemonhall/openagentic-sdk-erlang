-module(openagentic_events).
-export([system_init/3, user_message/1, user_compaction/2, user_question/3, hook_event/7, assistant_delta/1, tool_use/3, tool_result/5, tool_output_compacted/2, provider_event/1, assistant_message/1, assistant_message/2, workflow_init/5, workflow_step_start/5, workflow_step_output/6, workflow_step_event/5, workflow_guard_fail/5, workflow_step_pass/4, workflow_transition/5, workflow_cancelled/4, workflow_done/5, result/7, result/2, runtime_error/5, runtime_error/2]).

system_init(SessionId, Cwd, Extra) -> openagentic_events_messages:system_init(SessionId, Cwd, Extra).
user_message(Text) -> openagentic_events_messages:user_message(Text).
user_compaction(Auto0, Reason0) -> openagentic_events_messages:user_compaction(Auto0, Reason0).
user_question(QuestionId, Prompt, Choices) -> openagentic_events_messages:user_question(QuestionId, Prompt, Choices).
hook_event(HookPoint, Name, Matched, DurationMs, Action, ErrorType, ErrorMessage) -> openagentic_events_tooling:hook_event(HookPoint, Name, Matched, DurationMs, Action, ErrorType, ErrorMessage).
assistant_delta(TextDelta0) -> openagentic_events_messages:assistant_delta(TextDelta0).
tool_use(ToolUseId, Name, Input) -> openagentic_events_tooling:tool_use(ToolUseId, Name, Input).
tool_result(ToolUseId, Output, IsError, ErrorType, ErrorMessage) -> openagentic_events_tooling:tool_result(ToolUseId, Output, IsError, ErrorType, ErrorMessage).
tool_output_compacted(ToolUseId0, CompactedTs0) -> openagentic_events_tooling:tool_output_compacted(ToolUseId0, CompactedTs0).
provider_event(JsonMap) -> openagentic_events_runtime:provider_event(JsonMap).
assistant_message(Text) -> openagentic_events_messages:assistant_message(Text).
assistant_message(Text, IsSummary0) -> openagentic_events_messages:assistant_message(Text, IsSummary0).
workflow_init(WorkflowId0, WorkflowName0, DslPath0, DslHash0, Extra0) -> openagentic_events_workflow:workflow_init(WorkflowId0, WorkflowName0, DslPath0, DslHash0, Extra0).
workflow_step_start(WorkflowId0, StepId0, Role0, Attempt0, StepSessionId0) -> openagentic_events_workflow:workflow_step_start(WorkflowId0, StepId0, Role0, Attempt0, StepSessionId0).
workflow_step_output(WorkflowId0, StepId0, Attempt0, StepSessionId0, Output0, OutputFormat0) -> openagentic_events_workflow:workflow_step_output(WorkflowId0, StepId0, Attempt0, StepSessionId0, Output0, OutputFormat0).
workflow_step_event(WorkflowId0, StepId0, StepSessionId0, StepEvent0, Extra0) -> openagentic_events_workflow:workflow_step_event(WorkflowId0, StepId0, StepSessionId0, StepEvent0, Extra0).
workflow_guard_fail(WorkflowId0, StepId0, Attempt0, GuardName0, Reasons0) -> openagentic_events_workflow:workflow_guard_fail(WorkflowId0, StepId0, Attempt0, GuardName0, Reasons0).
workflow_step_pass(WorkflowId0, StepId0, Attempt0, NextStepId0) -> openagentic_events_workflow:workflow_step_pass(WorkflowId0, StepId0, Attempt0, NextStepId0).
workflow_transition(WorkflowId0, FromStepId0, Outcome0, ToStepId0, Reason0) -> openagentic_events_workflow:workflow_transition(WorkflowId0, FromStepId0, Outcome0, ToStepId0, Reason0).
workflow_cancelled(WorkflowId0, StepId0, Reason0, By0) -> openagentic_events_workflow:workflow_cancelled(WorkflowId0, StepId0, Reason0, By0).
workflow_done(WorkflowId0, WorkflowName0, Status0, FinalText0, Extra0) -> openagentic_events_workflow:workflow_done(WorkflowId0, WorkflowName0, Status0, FinalText0, Extra0).
result(FinalText0, SessionId0, StopReason0, Usage0, ResponseId0, ProviderMetadata0, Steps0) -> openagentic_events_runtime:result(FinalText0, SessionId0, StopReason0, Usage0, ResponseId0, ProviderMetadata0, Steps0).
result(ResponseId, StopReason) -> openagentic_events_runtime:result(ResponseId, StopReason).
runtime_error(Phase0, ErrorType0, ErrorMessage0, Provider0, ToolUseId0) -> openagentic_events_runtime:runtime_error(Phase0, ErrorType0, ErrorMessage0, Provider0, ToolUseId0).
runtime_error(Message, Raw) -> openagentic_events_runtime:runtime_error(Message, Raw).
