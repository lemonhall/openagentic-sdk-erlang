-module(openagentic_workflow_engine_execution).
-export([execute/2,ensure_web_answerer/2,run_loop/2,run_one_step/4,run_one_step_attempt/5]).

execute(StartStepId, State0) ->
  try
    run_loop(openagentic_workflow_engine_utils:to_bin(StartStepId), State0)
  catch
    Class:Reason:Stack ->
      Extra = #{error_class => Class, error_reason => Reason, stacktrace => Stack},
      _ =
        openagentic_workflow_engine_state:append_wf_event(
          State0,
          openagentic_events:workflow_done(
            openagentic_workflow_engine_state:wf_id(State0),
            maps:get(workflow_name, State0, <<>>),
            <<"failed">>,
            openagentic_workflow_engine_utils:to_bin({Class, Reason}),
            Extra
          )
        ),
      {error, {Class, Reason}}
  end.

ensure_web_answerer(Opts0, WorkflowSessionId) ->
  Opts = openagentic_workflow_engine_utils:ensure_map(Opts0),
  case maps:get(web_user_answerer, Opts, undefined) of
    F when is_function(F, 1) ->
      Opts;
    _ ->
      case openagentic_workflow_engine_utils:to_bool_default(maps:get(web_hil, Opts, false), false) of
        true ->
          Opts#{web_user_answerer => fun (Q) -> openagentic_web_q:ask(WorkflowSessionId, Q) end};
        false ->
          Opts
      end
  end.

%% ---- main loop ----

run_loop(StepId0, State0) ->
  StepId = openagentic_workflow_engine_utils:to_bin(StepId0),
  case StepId of
    <<>> ->
      openagentic_workflow_engine_state:finalize(State0, <<"failed">>, <<"missing start step">>);
    _ ->
      StepsById = maps:get(steps_by_id, State0),
      case maps:find(StepId, StepsById) of
        error ->
          openagentic_workflow_engine_state:finalize(State0, <<"failed">>, iolist_to_binary([<<"unknown step: ">>, StepId]));
        {ok, StepRaw0} ->
          StepRaw = openagentic_workflow_engine_utils:ensure_map(StepRaw0),
          Attempt0 = maps:get(StepId, maps:get(step_attempts, State0, #{}), 0),
          Attempt = Attempt0 + 1,
          MaxAttempts = openagentic_workflow_engine_state:step_max_attempts(StepRaw, State0),
          case Attempt =< MaxAttempts of
            false ->
              Msg = iolist_to_binary([<<"max_attempts exceeded for step ">>, StepId]),
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"max_attempts">>, [Msg])),
              openagentic_workflow_engine_state:finalize(State0, <<"failed">>, Msg);
            true ->
              State1 = openagentic_workflow_engine_utils:put_in(State0, [step_attempts, StepId], Attempt),
              case openagentic_workflow_engine_state:step_executor_kind(StepRaw) of
                <<"fanout_join">> -> openagentic_workflow_engine_fanout_wait:run_fanout_join_step(StepId, StepRaw, Attempt, State1);
                _ -> run_one_step(StepId, StepRaw, Attempt, State1)
              end
          end
      end
  end.

run_one_step(StepId, StepRaw, Attempt, State0) ->
  run_one_step_attempt(StepId, StepRaw, Attempt, 0, State0).

run_one_step_attempt(StepId, StepRaw, Attempt, RetryCount0, State0) ->
  Role = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = openagentic_workflow_engine_state:create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = openagentic_workflow_engine_utils:to_bin(StepSessionId0),

  ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_step_start(openagentic_workflow_engine_state:wf_id(State0), StepId, Role, Attempt, StepSessionId)),

  case openagentic_workflow_engine_prompts:resolve_prompt(State0, StepRaw) of
    {ok, PromptText} ->
      InputText = openagentic_workflow_engine_prompts:bind_input(State0, StepRaw),
      Failures = maps:get(StepId, maps:get(step_failures, State0, #{}), []),
      ControllerText = maps:get(controller_input, State0, <<>>),
      UserPrompt = openagentic_workflow_engine_prompts:build_user_prompt(PromptText, ControllerText, InputText, Attempt, Failures),
      ExecRes = openagentic_workflow_engine_retry:run_step_executor_with_timeout(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
      case ExecRes of
        {ok, StepOut0} ->
          StepOut = openagentic_workflow_engine_utils:to_bin(StepOut0),
          OutFormat = openagentic_workflow_engine_contracts:infer_output_format(StepRaw),
          ok =
            openagentic_workflow_engine_state:append_wf_event(
              State0,
              openagentic_events:workflow_step_output(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, StepSessionId, StepOut, OutFormat)
            ),
          case openagentic_workflow_engine_contracts:eval_step_output(StepRaw, StepOut) of
            {ok, Parsed} ->
              State1 = openagentic_workflow_engine_utils:put_in(State0, [step_outputs, StepId], #{output => StepOut, parsed => Parsed, step_session_id => StepSessionId}),
              {Next, TransitionReason} = openagentic_workflow_engine_contracts:step_next(StepRaw, Parsed),
              ok = openagentic_workflow_engine_state:append_wf_event(State1, openagentic_events:workflow_step_pass(openagentic_workflow_engine_state:wf_id(State1), StepId, Attempt, Next)),
              ok = openagentic_workflow_engine_state:append_wf_event(State1, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State1), StepId, <<"pass">>, Next, TransitionReason)),
              case Next of
                null -> openagentic_workflow_engine_state:finalize(State1, <<"completed">>, StepOut);
                _ -> run_loop(Next, State1)
              end;
            {error, Reasons} ->
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"guards">>, Reasons)),
              NextFail = openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State0), StepId, <<"fail">>, NextFail, <<"guard_failed">>)),
              case NextFail of
                null -> openagentic_workflow_engine_state:finalize(State0, <<"failed">>, openagentic_workflow_engine_utils:join_bins(Reasons, <<"\n">>));
                _ ->
                  %% Persist failure reasons in memory so retries can self-correct.
                  StateFail = openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], Reasons),
                  run_loop(NextFail, StateFail)
              end
          end;
        {error, Reason} ->
          ReasonBin = openagentic_workflow_engine_utils:to_bin(Reason),
          case openagentic_workflow_engine_retry:maybe_retry_transient_provider_error(State0, StepId, StepRaw, Attempt, RetryCount0, ReasonBin) of
            {retry, RetryState} ->
              run_one_step_attempt(StepId, StepRaw, Attempt, RetryCount0 + 1, RetryState);
            no_retry ->
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"executor">>, [ReasonBin])),
              NextFail = openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State0), StepId, <<"fail">>, NextFail, <<"executor_failed">>)),
              case NextFail of
                null -> openagentic_workflow_engine_state:finalize(State0, <<"failed">>, ReasonBin);
                _ ->
                  StateFail = openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], [ReasonBin]),
                  run_loop(NextFail, StateFail)
              end
          end
      end;
    {error, Reason} ->
      ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"prompt">>, [openagentic_workflow_engine_utils:to_bin(Reason)])),
      openagentic_workflow_engine_state:finalize(State0, <<"failed">>, openagentic_workflow_engine_utils:to_bin(Reason))
  end.
