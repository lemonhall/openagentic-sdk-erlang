-module(openagentic_workflow_engine_fanout_wait).
-export([run_fanout_join_step/4,collect_fanout_results/2,wait_for_fanout/3,wait_for_fanout_for_test/3,record_fanout_result/4,take_pending_ref_by_step_id/2,take_pending_ref_by_step_id_loop/3,finalize_fanout_results/1,down_reason_to_result/2]).

run_fanout_join_step(StepId, StepRaw, Attempt, State0) ->
  Role = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = openagentic_workflow_engine_state:create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = openagentic_workflow_engine_utils:to_bin(StepSessionId0),
  ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_step_start(openagentic_workflow_engine_state:wf_id(State0), StepId, Role, Attempt, StepSessionId)),
  FanoutCfg = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"fanout">>, fanout], #{})),
  FanoutSteps = [openagentic_workflow_engine_utils:to_bin(S) || S <- openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(FanoutCfg, [<<"steps">>, steps], []))],
  JoinStep = openagentic_workflow_engine_utils:step_ref(FanoutCfg, [<<"join">>, join]),
  case collect_fanout_results(FanoutSteps, State0) of
    {ok, Results} ->
      State1 = openagentic_workflow_engine_fanout_child:persist_fanout_successes(FanoutSteps, Results, State0),
      ok = openagentic_workflow_engine_state:append_wf_event(State1, openagentic_events:workflow_step_pass(openagentic_workflow_engine_state:wf_id(State1), StepId, Attempt, JoinStep)),
      ok = openagentic_workflow_engine_state:append_wf_event(State1, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State1), StepId, <<"pass">>, JoinStep, <<"fanout_join_completed">>)),
      case JoinStep of
        null -> openagentic_workflow_engine_state:finalize(State1, <<"completed">>, <<"fanout_join_completed">>);
        _ -> openagentic_workflow_engine_execution:run_loop(JoinStep, State1)
      end;
    {error, Reasons} ->
      ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_guard_fail(openagentic_workflow_engine_state:wf_id(State0), StepId, Attempt, <<"fanout">>, Reasons)),
      NextFail = openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_fail">>, on_fail]),
      ok = openagentic_workflow_engine_state:append_wf_event(State0, openagentic_events:workflow_transition(openagentic_workflow_engine_state:wf_id(State0), StepId, <<"fail">>, NextFail, <<"fanout_join_failed">>)),
      case NextFail of
        null -> openagentic_workflow_engine_state:finalize(State0, <<"failed">>, openagentic_workflow_engine_utils:join_bins(Reasons, <<"\n">>));
        _ ->
          StateFail = openagentic_workflow_engine_utils:put_in(State0, [step_failures, StepId], Reasons),
          openagentic_workflow_engine_execution:run_loop(NextFail, StateFail)
      end
  end.

collect_fanout_results(StepIds0, State0) ->
  StepIds = openagentic_workflow_engine_utils:uniq_bins(StepIds0),
  Parent = self(),
  Sink = fun (Ev) -> Parent ! {wf_event, Ev}, ok end,
  Pending =
    lists:foldl(
      fun (LeafStepId, Acc) ->
        {Pid, Ref} =
          spawn_monitor(
            fun () ->
              Parent ! {fanout_result, LeafStepId, openagentic_workflow_engine_fanout_child:safe_run_fanout_child(LeafStepId, State0, Sink)}
            end
          ),
        Acc#{Ref => #{step_id => LeafStepId, pid => Pid}}
      end,
      #{},
      StepIds
    ),
  wait_for_fanout(Pending, #{}, State0).

wait_for_fanout(Pending, Results, _State0) when map_size(Pending) =:= 0 ->
  finalize_fanout_results(Results);

wait_for_fanout(Pending, Results0, State0) ->
  receive
    {wf_event, Ev} ->
      ok = openagentic_workflow_engine_state:append_wf_event(State0, Ev),
      _ = (catch openagentic_workflow_mgr:note_progress(openagentic_workflow_engine_utils:to_bin(maps:get(workflow_session_id, State0, <<>>)), Ev)),
      wait_for_fanout(Pending, Results0, State0);
    {fanout_result, StepId, Result} ->
      {Pending1, Results1} = record_fanout_result(StepId, Result, Pending, Results0),
      wait_for_fanout(Pending1, Results1, State0);
    {'DOWN', Ref, process, _Pid, Reason} ->
      case maps:take(Ref, Pending) of
        error ->
          wait_for_fanout(Pending, Results0, State0);
        {#{step_id := StepId}, Pending1} ->
          Results1 =
            case maps:is_key(StepId, Results0) of
              true -> Results0;
              false -> Results0#{StepId => down_reason_to_result(StepId, Reason)}
            end,
          wait_for_fanout(Pending1, Results1, State0)
      end
  end.

-ifdef(TEST).

wait_for_fanout_for_test(Pending, Results, State) ->
  wait_for_fanout(Pending, Results, State).
-endif.

record_fanout_result(StepId, Result, Pending0, Results0) ->
  Results1 = Results0#{StepId => Result},
  case take_pending_ref_by_step_id(StepId, Pending0) of
    {ok, _Ref, Pending1} ->
      {Pending1, Results1};
    error ->
      {Pending0, Results1}
  end.

take_pending_ref_by_step_id(StepId, Pending0) ->
  Pending = openagentic_workflow_engine_utils:ensure_map(Pending0),
  take_pending_ref_by_step_id_loop(StepId, maps:to_list(Pending), Pending).

take_pending_ref_by_step_id_loop(_StepId, [], _Pending) ->
  error;
take_pending_ref_by_step_id_loop(StepId, [{Ref, Meta0} | Rest], Pending) ->
  Meta = openagentic_workflow_engine_utils:ensure_map(Meta0),
  case openagentic_workflow_engine_utils:to_bin(maps:get(step_id, Meta, maps:get(<<"step_id">>, Meta, <<>>))) =:= openagentic_workflow_engine_utils:to_bin(StepId) of
    true -> {ok, Ref, maps:remove(Ref, Pending)};
    false -> take_pending_ref_by_step_id_loop(StepId, Rest, Pending)
  end.

finalize_fanout_results(Results) ->
  case [openagentic_workflow_engine_fanout_child:format_fanout_reason(StepId, Reason) || {StepId, {error, Reason}} <- maps:to_list(Results)] of
    [] -> {ok, Results};
    Reasons -> {error, Reasons}
  end.

down_reason_to_result(_StepId, normal) ->
  {error, [<<"fanout child exited before returning a result">>]};
down_reason_to_result(_StepId, Reason) ->
  {error, [iolist_to_binary(io_lib:format("fanout child crashed: ~p", [Reason]))]}.
