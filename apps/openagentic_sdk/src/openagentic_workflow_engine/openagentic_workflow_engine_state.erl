-module(openagentic_workflow_engine_state).
-export([workflow_workspace_dir/2,create_step_session/4,append_wf_event/2,append_wf_event/3,finalize/3,wf_id/1,step_max_attempts/2,step_max_steps/3,step_timeout_ms/2,step_executor_kind/1]).
-define(DEFAULT_MAX_STEPS, 50).

workflow_workspace_dir(SessionRoot0, WorkflowSessionId0) ->
  SessionRoot = openagentic_workflow_engine_utils:ensure_list_str(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_engine_utils:ensure_list_str(WorkflowSessionId0),
  Dir = openagentic_session_store:session_dir(SessionRoot, WorkflowSessionId),
  filename:join([Dir, "workspace"]).

create_step_session(State0, StepId, Role, Attempt) ->
  Root = maps:get(session_root, State0),
  TimeContext = maps:get(time_context, State0, undefined),
  Meta =
    #{
      workflow_id => wf_id(State0),
      step_id => StepId,
      role => Role,
      attempt => Attempt,
      time_context => TimeContext
    },
  {ok, Sid} = openagentic_session_store:create_session(Root, Meta),
  SidBin = openagentic_workflow_engine_utils:to_bin(Sid),
  ok = append_wf_event(Root, Sid, openagentic_events:system_init(SidBin, maps:get(project_dir, State0), #{time_context => TimeContext})),
  Sid.

append_wf_event(State0, Ev) ->
  case maps:get(workflow_event_sink, State0, undefined) of
    F when is_function(F, 1) ->
      F(Ev);
    _ ->
      append_wf_event(maps:get(session_root, State0), maps:get(workflow_session_id, State0), Ev)
  end.

append_wf_event(Root0, Sid0, Ev) ->
  Root = openagentic_workflow_engine_utils:ensure_list_str(Root0),
  Sid = openagentic_workflow_engine_utils:ensure_list_str(Sid0),
  {ok, _Stored} = openagentic_session_store:append_event(Root, Sid, Ev),
  _ = (catch openagentic_workflow_mgr:note_progress(Sid, Ev)),
  ok.

finalize(State0, Status0, FinalText0) ->
  Status = openagentic_workflow_engine_utils:to_bin(Status0),
  FinalText = openagentic_workflow_engine_utils:to_bin(FinalText0),
  ok =
    append_wf_event(
      State0,
      openagentic_events:workflow_done(wf_id(State0), maps:get(workflow_name, State0, <<>>), Status, FinalText, #{})
    ),
  {ok, #{
    workflow_id => wf_id(State0),
    workflow_name => maps:get(workflow_name, State0, <<>>),
    workflow_session_id => openagentic_workflow_engine_utils:to_bin(maps:get(workflow_session_id, State0)),
    status => Status,
    final_text => FinalText
  }}.

wf_id(State0) ->
  maps:get(workflow_id, State0, <<>>).

%% ---- step defaults ----

step_max_attempts(StepRaw, State0) ->
  StepMax = openagentic_workflow_engine_utils:get_any(StepRaw, [<<"max_attempts">>, max_attempts], undefined),
  Defaults = openagentic_workflow_engine_utils:ensure_map(maps:get(defaults, State0, #{})),
  DefMax = openagentic_workflow_engine_utils:get_any(Defaults, [<<"max_attempts">>, max_attempts], 1),
  openagentic_workflow_engine_utils:int_or_default(StepMax, openagentic_workflow_engine_utils:int_or_default(DefMax, 1)).

step_max_steps(StepRaw, State0, Fallback) ->
  StepMax = openagentic_workflow_engine_utils:get_any(StepRaw, [<<"max_steps">>, max_steps], undefined),
  Defaults = openagentic_workflow_engine_utils:ensure_map(maps:get(defaults, State0, #{})),
  DefMax = openagentic_workflow_engine_utils:get_any(Defaults, [<<"max_steps">>, max_steps], undefined),
  openagentic_workflow_engine_utils:int_or_default(StepMax, openagentic_workflow_engine_utils:int_or_default(DefMax, openagentic_workflow_engine_utils:int_or_default(Fallback, ?DEFAULT_MAX_STEPS))).

step_timeout_ms(StepRaw, State0) ->
  StepSec = openagentic_workflow_engine_utils:get_any(StepRaw, [<<"timeout_seconds">>, timeout_seconds], undefined),
  Defaults = openagentic_workflow_engine_utils:ensure_map(maps:get(defaults, State0, #{})),
  DefSec = openagentic_workflow_engine_utils:get_any(Defaults, [<<"timeout_seconds">>, timeout_seconds], undefined),
  Sec0 = openagentic_workflow_engine_utils:int_or_default(StepSec, openagentic_workflow_engine_utils:int_or_default(DefSec, 600)),
  Sec = openagentic_workflow_engine_utils:clamp_int(Sec0, 1, 3600),
  Sec * 1000.

step_executor_kind(StepRaw) ->
  Exec = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"executor">>, executor], <<>>)),
  case Exec of
    <<"fanout_join">> -> <<"fanout_join">>;
    _ -> <<"local_otp">>
  end.

%% ---- file/hash helpers ----
