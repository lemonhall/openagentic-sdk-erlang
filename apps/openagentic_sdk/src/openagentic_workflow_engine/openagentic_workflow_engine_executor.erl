-module(openagentic_workflow_engine_executor).
-export([run_step_executor/7,default_step_executor/7]).
-define(DEFAULT_MAX_STEPS, 50).

run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts = maps:get(opts, State0, #{}),
  Ctx =
    #{
      project_dir => openagentic_workflow_engine_utils:to_bin(maps:get(project_dir, State0)),
      session_root => openagentic_workflow_engine_utils:to_bin(maps:get(session_root, State0)),
      workflow_id => openagentic_workflow_engine_state:wf_id(State0),
      workflow_session_id => openagentic_workflow_engine_utils:to_bin(maps:get(workflow_session_id, State0)),
      step_id => StepId,
      role => Role,
      attempt => Attempt,
      step_session_id => openagentic_workflow_engine_utils:to_bin(StepSessionId0),
      time_context => maps:get(time_context, State0, undefined),
      user_prompt => UserPrompt
    },
  case maps:get(step_executor, Opts, undefined) of
    F1 when is_function(F1, 1) ->
      F1(Ctx);
    F2 when is_function(F2, 2) ->
      F2(Ctx, StepRaw);
    _ ->
      default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw)
  end.

default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts0 = maps:get(opts, State0, #{}),
  MaxSteps = openagentic_workflow_engine_state:step_max_steps(StepRaw, State0, maps:get(max_steps, Opts0, ?DEFAULT_MAX_STEPS)),
  {Gate, AllowedTools} = openagentic_workflow_engine_tooling:tool_policy_for_step(StepRaw, State0),
  WfId = openagentic_workflow_engine_state:wf_id(State0),
  WfSid = openagentic_workflow_engine_utils:to_bin(maps:get(workflow_session_id, State0, <<>>)),
  StepSessionIdBin = openagentic_workflow_engine_utils:to_bin(StepSessionId0),
  %% Bridge step events (tool.use/tool.result/user.question/assistant.* etc.) into the workflow session,
  %% so the web UI can observe and answer HITL prompts.
   BridgeSink =
      fun (Ev0) ->
        Ev = openagentic_workflow_engine_utils:ensure_map(Ev0),
       StepSeq = maps:get(seq, Ev, maps:get(<<"seq">>, Ev, undefined)),
       StepTs = maps:get(ts, Ev, maps:get(<<"ts">>, Ev, undefined)),
      %% NOTE: jsone:encode/1 crashes on `undefined`. Step events like assistant.delta
      %% are transient and may not carry seq/ts, so only include them when present.
      Extra0 = #{},
      Extra1 =
        case StepSeq of
          undefined -> Extra0;
          _ -> Extra0#{step_seq => StepSeq}
        end,
      Extra =
        case StepTs of
          undefined -> Extra1;
          _ -> Extra1#{step_ts => StepTs}
        end,
       _ = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_step_event(WfId, StepId, StepSessionIdBin, Ev, Extra)),
       _ = (catch openagentic_workflow_mgr:note_progress(WfSid, Ev)),
        ok
      end,
  WebAnswerer0 = maps:get(web_user_answerer, Opts0, undefined),
  WebAnswerer =
    case WebAnswerer0 of
      F when is_function(F, 1) -> F;
      _ -> undefined
    end,
  UserAnswerer =
    case WebAnswerer of
      undefined ->
        maps:get(user_answerer, Opts0, undefined);
      _ ->
        WebAnswerer
    end,
  %% Ensure the permission gate uses the effective userAnswerer for this run.
  %% In web mode, the CLI-provided user_answerer may be unsupported (io:get_line/1 -> {error,enotsup}).
  Gate2 =
    case UserAnswerer of
      AnswererFun when is_function(AnswererFun, 1) ->
        GateMap = openagentic_workflow_engine_utils:ensure_map(Gate),
        GateMap#{user_answerer => AnswererFun};
      _ -> openagentic_workflow_engine_utils:ensure_map(Gate)
    end,
  RuntimeOpts =
    Opts0#{
      project_dir => maps:get(project_dir, State0),
      workspace_dir => maps:get(workspace_dir, State0, undefined),
      cwd => maps:get(project_dir, State0),
      session_root => maps:get(session_root, State0),
      resume_session_id => StepSessionId0,
      system_prompt => openagentic_workflow_engine_tooling:role_system_prompt(Role, StepId, Attempt),
      max_steps => MaxSteps,
      permission_gate => Gate2,
      allowed_tools => AllowedTools,
      user_answerer => UserAnswerer,
      event_sink => BridgeSink
    },
  case openagentic_runtime:query(UserPrompt, RuntimeOpts) of
    {ok, #{final_text := Txt}} -> {ok, Txt};
    {ok, _Other} -> {ok, <<>>};
    {error, Reason} -> {error, Reason}
  end.
