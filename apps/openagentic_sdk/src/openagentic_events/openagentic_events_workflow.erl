-module(openagentic_events_workflow).
-export([workflow_cancelled/4, workflow_done/5, workflow_guard_fail/5, workflow_init/5, workflow_step_event/5, workflow_step_output/6, workflow_step_pass/4, workflow_step_start/5, workflow_transition/5]).

workflow_init(WorkflowId0, WorkflowName0, DslPath0, DslHash0, Extra0) ->
  Base = #{type => <<"workflow.init">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), workflow_name => openagentic_events_utils:to_bin(WorkflowName0), dsl_path => openagentic_events_utils:to_bin(DslPath0), dsl_sha256 => openagentic_events_utils:to_bin(DslHash0)},
  maps:merge(Base, case Extra0 of M when is_map(M) -> M; _ -> #{} end).

workflow_step_start(WorkflowId0, StepId0, Role0, Attempt0, StepSessionId0) ->
  #{type => <<"workflow.step.start">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0), role => openagentic_events_utils:to_bin(Role0), attempt => openagentic_events_utils:to_int(Attempt0), step_session_id => openagentic_events_utils:to_bin(StepSessionId0)}.

workflow_step_output(WorkflowId0, StepId0, Attempt0, StepSessionId0, Output0, OutputFormat0) ->
  Base = #{type => <<"workflow.step.output">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0), attempt => openagentic_events_utils:to_int(Attempt0), step_session_id => openagentic_events_utils:to_bin(StepSessionId0), output => Output0},
  case OutputFormat0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; F -> Base#{output_format => openagentic_events_utils:to_bin(F)} end.

workflow_step_event(WorkflowId0, StepId0, StepSessionId0, StepEvent0, Extra0) ->
  Base = #{type => <<"workflow.step.event">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0), step_session_id => openagentic_events_utils:to_bin(StepSessionId0), step_event => openagentic_events_utils:ensure_map(StepEvent0)},
  maps:merge(Base, openagentic_events_utils:drop_undefined(case Extra0 of M when is_map(M) -> M; _ -> #{} end)).

workflow_guard_fail(WorkflowId0, StepId0, Attempt0, GuardName0, Reasons0) ->
  Reasons = case Reasons0 of L when is_list(L) -> [openagentic_events_utils:to_bin(R) || R <- L]; B when is_binary(B) -> [B]; _ -> [] end,
  Base = #{type => <<"workflow.guard.fail">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0), attempt => openagentic_events_utils:to_int(Attempt0)},
  Base2 = case GuardName0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; G -> Base#{guard => openagentic_events_utils:to_bin(G)} end,
  Base2#{reasons => Reasons}.

workflow_step_pass(WorkflowId0, StepId0, Attempt0, NextStepId0) ->
  Base = #{type => <<"workflow.step.pass">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0), attempt => openagentic_events_utils:to_int(Attempt0)},
  case NextStepId0 of null -> Base; undefined -> Base; <<>> -> Base; "" -> Base; Next -> Base#{next_step_id => openagentic_events_utils:to_bin(Next)} end.

workflow_transition(WorkflowId0, FromStepId0, Outcome0, ToStepId0, Reason0) ->
  Base = #{type => <<"workflow.transition">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), from_step_id => openagentic_events_utils:to_bin(FromStepId0), outcome => openagentic_events_utils:to_bin(Outcome0)},
  Base2 = case ToStepId0 of null -> Base; undefined -> Base; <<>> -> Base; "" -> Base; To -> Base#{to_step_id => openagentic_events_utils:to_bin(To)} end,
  case Reason0 of undefined -> Base2; null -> Base2; <<>> -> Base2; "" -> Base2; R -> Base2#{reason => openagentic_events_utils:to_bin(R)} end.

workflow_cancelled(WorkflowId0, StepId0, Reason0, By0) ->
  Base = #{type => <<"workflow.cancelled">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), step_id => openagentic_events_utils:to_bin(StepId0)},
  Base2 = case Reason0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; R -> Base#{reason => openagentic_events_utils:to_bin(R)} end,
  case By0 of undefined -> Base2; null -> Base2; <<>> -> Base2; "" -> Base2; B -> Base2#{by => openagentic_events_utils:to_bin(B)} end.

workflow_done(WorkflowId0, WorkflowName0, Status0, FinalText0, Extra0) ->
  Base = #{type => <<"workflow.done">>, workflow_id => openagentic_events_utils:to_bin(WorkflowId0), workflow_name => openagentic_events_utils:to_bin(WorkflowName0), status => openagentic_events_utils:to_bin(Status0), final_text => openagentic_events_utils:to_bin(FinalText0)},
  maps:merge(Base, case Extra0 of M when is_map(M) -> M; _ -> #{} end).
