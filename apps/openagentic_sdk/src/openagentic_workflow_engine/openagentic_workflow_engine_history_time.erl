-module(openagentic_workflow_engine_history_time).
-export([find_workflow_init/1,is_controller_message/1,recover_workflow_time_context/3,last_workflow_run_time_context/1,last_workflow_run_time_context_loop/1,event_time_context/1,reconstruct_step_outputs/1,reconstruct_step_failures/1]).

find_workflow_init(Events0) ->
  Events = openagentic_workflow_engine_utils:ensure_list_value(Events0),
  case [E || E <- Events, is_map(E) andalso openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) =:= <<"workflow.init">>] of
    [H | _] -> {ok, H};
    [] -> {error, missing_workflow_init}
  end.

is_controller_message(E0) ->
  E = openagentic_workflow_engine_utils:ensure_map(E0),
  openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) =:= <<"workflow.controller.message">>.

recover_workflow_time_context(Events0, Init0, Opts0) ->
  case last_workflow_run_time_context(Events0) of
    undefined ->
      case event_time_context(Init0) of
        undefined -> openagentic_time_context:resolve(Opts0);
        TimeContext -> TimeContext
      end;
    TimeContext ->
      TimeContext
  end.

last_workflow_run_time_context(Events0) ->
  Events = lists:reverse(openagentic_workflow_engine_utils:ensure_list_value(Events0)),
  last_workflow_run_time_context_loop(Events).

last_workflow_run_time_context_loop([]) ->
  undefined;
last_workflow_run_time_context_loop([E0 | Rest]) ->
  E = openagentic_workflow_engine_utils:ensure_map(E0),
  case openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) of
    <<"workflow.run.start">> -> event_time_context(E);
    _ -> last_workflow_run_time_context_loop(Rest)
  end.

event_time_context(E0) ->
  E = openagentic_workflow_engine_utils:ensure_map(E0),
  case maps:get(<<"time_context">>, E, maps:get(time_context, E, undefined)) of
    undefined -> undefined;
    null -> undefined;
    TimeContext -> openagentic_time_context:resolve(#{time_context => TimeContext})
  end.

reconstruct_step_outputs(Events0) ->
  Events = openagentic_workflow_engine_utils:ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Acc0) ->
      E = openagentic_workflow_engine_utils:ensure_map(E0),
      T = openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
      case T of
        <<"workflow.step.output">> ->
          StepId = openagentic_workflow_engine_utils:to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>))),
          Out = openagentic_workflow_engine_utils:to_bin(maps:get(<<"output">>, E, maps:get(output, E, <<>>))),
          StepSid = openagentic_workflow_engine_utils:to_bin(maps:get(<<"step_session_id">>, E, maps:get(step_session_id, E, <<>>))),
          Acc0#{StepId => #{output => Out, parsed => #{}, step_session_id => StepSid}};
        _ ->
          Acc0
      end
    end,
    #{},
    Events
  ).

reconstruct_step_failures(Events0) ->
  Events = openagentic_workflow_engine_utils:ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Acc0) ->
      E = openagentic_workflow_engine_utils:ensure_map(E0),
      T = openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
      case T of
        <<"workflow.guard.fail">> ->
          StepId = openagentic_workflow_engine_utils:to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>))),
          Reasons0 = openagentic_workflow_engine_utils:ensure_list_value(maps:get(<<"reasons">>, E, maps:get(reasons, E, []))),
          Reasons = [openagentic_workflow_engine_utils:to_bin(X) || X <- Reasons0],
          Acc0#{StepId => Reasons};
        _ ->
          Acc0
      end
    end,
    #{},
    Events
  ).
