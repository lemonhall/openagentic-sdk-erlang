-module(openagentic_workflow_engine_history_steps).
-export([pick_continue_step/2,last_workflow_done/1,last_step_id_before/4,last_step_id_before_loop/4]).

pick_continue_step(Events0, DefaultStart0) ->
  Events = openagentic_workflow_engine_utils:ensure_list_value(Events0),
  DefaultStart = openagentic_workflow_engine_utils:to_bin(DefaultStart0),
  %% Semantics:
  %% - If the previous run completed: start from the workflow default start step (new input may change everything).
  %% - If the previous run failed: resume from the last started step (to fix blocking input).
  {Status, DoneIdx} = last_workflow_done(Events),
  case Status of
    <<"completed">> ->
      DefaultStart;
    <<"failed">> ->
      case last_step_id_before(Events, DoneIdx, <<"workflow.step.start">>, <<"step_id">>) of
        <<>> -> DefaultStart;
        S -> S
      end;
    _ ->
      DefaultStart
  end.

last_workflow_done(Events) ->
  %% Returns {StatusBin, Index} (0-based), or {<<>>, -1} if not found.
  last_workflow_done(Events, 0, {<<>>, -1}).

last_workflow_done([], _Idx, Acc) ->
  Acc;
last_workflow_done([E0 | Rest], Idx, {BestStatus, BestIdx}) ->
  E = openagentic_workflow_engine_utils:ensure_map(E0),
  T = openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  Acc =
    case T of
      <<"workflow.done">> ->
        Status = openagentic_workflow_engine_utils:to_bin(maps:get(<<"status">>, E, maps:get(status, E, <<>>))),
        {Status, Idx};
      _ ->
        {BestStatus, BestIdx}
    end,
  last_workflow_done(Rest, Idx + 1, Acc).

last_step_id_before(Events, DoneIdx, Type, Key) ->
  case DoneIdx of
    I when is_integer(I), I >= 0 ->
      Prefix = lists:sublist(Events, I),
      last_step_id_before_loop(Prefix, openagentic_workflow_engine_utils:to_bin(Type), openagentic_workflow_engine_utils:to_bin(Key), <<>>);
    _ ->
      last_step_id_before_loop(Events, openagentic_workflow_engine_utils:to_bin(Type), openagentic_workflow_engine_utils:to_bin(Key), <<>>)
  end.

last_step_id_before_loop([], _Type, _Key, Best) ->
  Best;
last_step_id_before_loop([E0 | Rest], Type, Key, Best0) ->
  E = openagentic_workflow_engine_utils:ensure_map(E0),
  T = openagentic_workflow_engine_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  Best =
    case T =:= Type of
      true ->
        case Key of
          <<"step_id">> -> openagentic_workflow_engine_utils:to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>)));
          _ -> openagentic_workflow_engine_utils:to_bin(maps:get(Key, E, <<>>))
        end;
      false ->
        Best0
    end,
  last_step_id_before_loop(Rest, Type, Key, Best).
