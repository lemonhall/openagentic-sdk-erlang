-module(openagentic_workflow_engine_fanout_child).
-export([safe_run_fanout_child/3,run_fanout_child/3,run_fanout_child_attempt/3,run_fanout_child_once/4,persist_fanout_successes/3,format_fanout_reason/2]).

safe_run_fanout_child(StepId, State0, Sink) ->
  try
    run_fanout_child(StepId, State0, Sink)
  catch
    Class:Reason ->
      {error, [iolist_to_binary(io_lib:format("fanout child crashed: ~p:~p", [Class, Reason]))]}
  end.

run_fanout_child(StepId, State0, Sink) ->
  StepRaw = openagentic_workflow_engine_utils:ensure_map(maps:get(StepId, maps:get(steps_by_id, State0))),
  ChildState = State0#{workflow_event_sink => Sink},
  run_fanout_child_attempt(StepId, StepRaw, ChildState).

run_fanout_child_attempt(StepId, StepRaw, State0) ->
  Attempt0 = maps:get(StepId, maps:get(step_attempts, State0, #{}), 0),
  Attempt = Attempt0 + 1,
  MaxAttempts = openagentic_workflow_engine_state:step_max_attempts(StepRaw, State0),
  case Attempt =< MaxAttempts of
    false ->
      Msg = iolist_to_binary([<<"max_attempts exceeded for step ">>, StepId]),
      ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"max_attempts">>, [Msg])),
      {error, [Msg]};
    true ->
      State1 = openagentic_workflow_engine_utils:put_in(State0, [step_attempts, StepId], Attempt),
      run_fanout_child_once(StepId, StepRaw, Attempt, State1)
  end.

run_fanout_child_once(StepId, StepRaw, Attempt, State0) ->
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
          case openagentic_workflow_engine_contracts:eval_step_output(StepRaw, StepOut) of
            {ok, Parsed} ->
              {ok, #{attempt => Attempt, output => StepOut, parsed => Parsed, output_format => OutFormat, step_session_id => StepSessionId}};
            {error, Reasons} ->
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"guards">>, Reasons)),
              NextFail = openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State0), StepId, <<"fail">>, NextFail, <<"guard_failed">>)),
              case NextFail of
                StepId ->
                  StateFail = openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], Reasons),
                  run_fanout_child_attempt(StepId, StepRaw, StateFail);
                null ->
                  {error, Reasons};
                _ ->
                  {error, [iolist_to_binary([<<"unsupported fanout on_fail route: ">>, openagentic_workflow_engine_utils:to_bin(NextFail)]) | Reasons]}
              end
          end;
        {error, Reason} ->
          ReasonBin = openagentic_workflow_engine_utils:to_bin(Reason),
          ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"executor">>, [ReasonBin])),
          NextFail = openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_fail">>, on_fail]),
          ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State0), StepId, <<"fail">>, NextFail, <<"executor_failed">>)),
          case NextFail of
            StepId ->
              StateFail = openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], [ReasonBin]),
              run_fanout_child_attempt(StepId, StepRaw, StateFail);
            null ->
              {error, [ReasonBin]};
            _ ->
              {error, [iolist_to_binary([<<"unsupported fanout on_fail route: ">>, openagentic_workflow_engine_utils:to_bin(NextFail)]), ReasonBin]}
          end
      end;
    {error, Reason} ->
      ReasonBin = openagentic_workflow_engine_utils:to_bin(Reason),
      ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"prompt">>, [ReasonBin])),
      {error, [ReasonBin]}
  end.

persist_fanout_successes(StepIds, Results, State0) ->
  lists:foldl(
    fun (StepId, AccState0) ->
      {ok, #{attempt := Attempt, output := StepOut, parsed := Parsed, output_format := OutFormat, step_session_id := StepSessionId}} = maps:get(StepId, Results),
      AccState1 = openagentic_workflow_engine_utils:put_in(AccState0, [step_outputs, StepId], #{output => StepOut, parsed => Parsed, step_session_id => StepSessionId}),
      ok = openagentic_workflow_engine_state:append_wf_event(AccState1, openagentic_events:workflow_step_output(openagentic_workflow_engine_state:wf_id(AccState1), StepId, Attempt, StepSessionId, StepOut, OutFormat)),
      ok = openagentic_workflow_engine_state:append_wf_event(AccState1, openagentic_events:workflow_step_pass(openagentic_workflow_engine_state:wf_id(AccState1), StepId, Attempt, null)),
      ok = openagentic_workflow_engine_state:append_wf_event(AccState1, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(AccState1), StepId, <<"pass">>, null, <<"fanout_leaf_completed">>)),
      AccState1
    end,
    State0,
    StepIds
  ).

format_fanout_reason(StepId, Reasons) when is_list(Reasons) ->
  iolist_to_binary([StepId, <<": ">>, openagentic_workflow_engine_utils:join_bins(Reasons, <<"; ">>)]);
format_fanout_reason(StepId, Reason) ->
  iolist_to_binary([StepId, <<": ">>, openagentic_workflow_engine_utils:to_bin(Reason)]).

%% ---- executor ----
