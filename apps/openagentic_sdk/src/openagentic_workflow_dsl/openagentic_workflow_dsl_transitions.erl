-module(openagentic_workflow_dsl_transitions).
-export([validate_terminal_path/3, validate_transitions/3, validate_step_ref/4, validate_step_refs/4]).

validate_transitions(StepInfos, StepIdSet, Errors0) ->
  lists:foldl(
    fun (#{id := Id, executor := Exec, on_pass := OnPass, on_fail := OnFail, on_decision := OnDecision, fanout_steps := FanoutSteps, join := Join}, Acc) ->
      Acc1 = case Exec of <<"fanout_join">> -> Acc; _ -> validate_step_ref(iolist_to_binary([<<"steps.">>, Id, <<".on_pass">>]), OnPass, StepIdSet, Acc) end,
      Acc2 = validate_step_ref(iolist_to_binary([<<"steps.">>, Id, <<".on_fail">>]), OnFail, StepIdSet, Acc1),
      Acc3 = openagentic_workflow_dsl_guards:validate_on_decision_refs(iolist_to_binary([<<"steps.">>, Id, <<".on_decision">>]), OnDecision, StepIdSet, Acc2),
      Acc4 = validate_step_refs(iolist_to_binary([<<"steps.">>, Id, <<".fanout.steps">>]), FanoutSteps, StepIdSet, Acc3),
      validate_step_ref(iolist_to_binary([<<"steps.">>, Id, <<".fanout.join">>]), Join, StepIdSet, Acc4)
    end,
    Errors0,
    StepInfos
  ).

validate_terminal_path(StepInfos, StepIdSet, Errors0) ->
  case StepInfos of
    [] -> Errors0;
    [#{id := StartId} | _] ->
      Visited = reachable_steps(StartId, StepInfos, StepIdSet, #{}),
      HasTerminal =
        lists:any(
          fun (#{id := Id, executor := Exec, on_pass := OnPass, on_fail := OnFail, join := Join}) ->
            case maps:get(Id, Visited, false) of
              false -> false;
              true ->
                (OnPass =:= null)
                orelse (OnFail =:= null)
                orelse ((Exec =:= <<"fanout_join">>) andalso (Join =:= null))
            end
          end,
          StepInfos
        ),
      case HasTerminal of
        true -> Errors0;
        false -> [openagentic_workflow_dsl_utils:err(<<"$">>, <<"no_terminal">>, <<"no terminal step reachable from start">>) | Errors0]
      end
  end.

reachable_steps(StartId, StepInfos, StepIdSet, Visited0) ->
  case maps:get(StartId, Visited0, false) of
    true -> Visited0;
    false ->
      Visited1 = Visited0#{StartId => true},
      case find_step(StartId, StepInfos) of
        undefined -> Visited1;
        #{on_pass := OnPass, on_fail := OnFail, on_decision := OnDecision, fanout_steps := FanoutSteps, join := Join} ->
          Visited2 = follow_ref(OnPass, StepInfos, StepIdSet, Visited1),
          Visited3 = follow_ref(OnFail, StepInfos, StepIdSet, Visited2),
          Visited4 = follow_refs_in_map(OnDecision, StepInfos, StepIdSet, Visited3),
          Visited5 = follow_refs_in_list(FanoutSteps, StepInfos, StepIdSet, Visited4),
          follow_ref(Join, StepInfos, StepIdSet, Visited5)
      end
  end.

follow_refs_in_list([], _StepInfos, _StepIdSet, Visited0) -> Visited0;
follow_refs_in_list([Ref | Rest], StepInfos, StepIdSet, Visited0) ->
  follow_refs_in_list(Rest, StepInfos, StepIdSet, follow_ref(Ref, StepInfos, StepIdSet, Visited0)).

follow_refs_in_map(Map0, StepInfos, StepIdSet, Visited0) ->
  Map = openagentic_workflow_dsl_utils:ensure_map(Map0),
  lists:foldl(fun ({_K, V}, Acc) -> follow_ref(V, StepInfos, StepIdSet, Acc) end, Visited0, maps:to_list(Map)).

follow_ref(null, _StepInfos, _StepIdSet, Visited) -> Visited;
follow_ref(undefined, _StepInfos, _StepIdSet, Visited) -> Visited;
follow_ref(Ref, StepInfos, StepIdSet, Visited) when is_binary(Ref) ->
  case maps:get(Ref, StepIdSet, false) of true -> reachable_steps(Ref, StepInfos, StepIdSet, Visited); false -> Visited end;
follow_ref(_Other, _StepInfos, _StepIdSet, Visited) -> Visited.

find_step(_Id, []) -> undefined;
find_step(Id, [#{id := Id} = S | _]) -> S;
find_step(Id, [_ | Rest]) -> find_step(Id, Rest).

validate_step_ref(_Path, null, _StepIdSet, Errors) -> Errors;
validate_step_ref(Path, Ref, StepIdSet, Errors) when is_binary(Ref) ->
  case maps:get(Ref, StepIdSet, false) of
    true -> Errors;
    false -> [openagentic_workflow_dsl_utils:err(Path, <<"unknown_step">>, iolist_to_binary([<<"unknown step: ">>, Ref])) | Errors]
  end;
validate_step_ref(Path, undefined, _StepIdSet, Errors) -> [openagentic_workflow_dsl_utils:err(Path, <<"missing">>, <<"step ref is required (or null)">>) | Errors];
validate_step_ref(Path, _Other, _StepIdSet, Errors) -> [openagentic_workflow_dsl_utils:err(Path, <<"invalid_type">>, <<"step ref must be a string or null">>) | Errors].

validate_step_refs(_Path, [], _StepIdSet, Errors) -> Errors;
validate_step_refs(Path, Refs, StepIdSet, Errors0) when is_list(Refs) ->
  lists:foldl(fun (Ref, Acc) -> validate_step_ref(Path, Ref, StepIdSet, Acc) end, Errors0, Refs);
validate_step_refs(Path, _Other, _StepIdSet, Errors) ->
  [openagentic_workflow_dsl_utils:err(Path, <<"invalid_type">>, <<"step refs must be an array">>) | Errors].
