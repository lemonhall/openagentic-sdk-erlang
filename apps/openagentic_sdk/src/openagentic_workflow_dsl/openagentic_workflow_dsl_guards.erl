-module(openagentic_workflow_dsl_guards).
-export([validate_guards/3, validate_on_decision/3, validate_on_decision_refs/4]).

validate_guards(Path0, Guards, Errors0) ->
  validate_guards(Path0, Guards, 0, Errors0).

validate_guards(_Path0, [], _Idx, Errors) -> Errors;
validate_guards(Path0, [G0 | Rest], Idx, Errors0) ->
  Path = iolist_to_binary([Path0, <<"[">>, integer_to_binary(Idx), <<"]">>]),
  G = openagentic_workflow_dsl_utils:ensure_map(G0),
  T = openagentic_workflow_dsl_utils:get_bin(G, [<<"type">>, type], <<>>),
  Errors1 =
    case T of
      <<"max_words">> -> Errors0;
      <<"regex_must_match">> ->
        P = openagentic_workflow_dsl_utils:get_bin(G, [<<"pattern">>, pattern], <<>>),
        openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".pattern">>]), P, <<"pattern is required">>, Errors0);
      <<"markdown_sections">> ->
        Req0 = openagentic_workflow_dsl_utils:get_any(G, [<<"required">>, required], undefined),
        {_Req, ErrorsX} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".required">>]), Req0, <<"required must be an array">>, Errors0),
        ErrorsX;
      <<"decision_requires_reasons">> ->
        W = openagentic_workflow_dsl_utils:get_bin(G, [<<"when">>, 'when'], <<>>),
        openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".when">>]), W, <<"when is required">>, Errors0);
      <<"requires_evidence">> ->
        Cmds0 = openagentic_workflow_dsl_utils:get_any(G, [<<"commands">>, commands], undefined),
        {_Cmds, ErrorsX} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".commands">>]), Cmds0, <<"commands must be an array">>, Errors0),
        ErrorsX;
      <<>> -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"guard.type is required">>) | Errors0];
      _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"unknown_guard_type">>, iolist_to_binary([<<"unknown guard type: ">>, T])) | Errors0]
    end,
  validate_guards(Path0, Rest, Idx + 1, Errors1).

validate_on_decision(_Path, undefined, Errors) -> {#{}, Errors};
validate_on_decision(_Path, null, Errors) -> {#{}, Errors};
validate_on_decision(Path, M0, Errors0) when is_map(M0) -> {M0, validate_on_decision_entries(Path, maps:to_list(M0), Errors0)};
validate_on_decision(Path, L0, Errors0) when is_list(L0) ->
  try
    M = maps:from_list(L0),
    {M, validate_on_decision_entries(Path, maps:to_list(M), Errors0)}
  catch
    _:_ -> {#{}, [openagentic_workflow_dsl_utils:err(Path, <<"not_object">>, <<"on_decision must be an object">>) | Errors0]}
  end;
validate_on_decision(Path, _Other, Errors0) -> {#{}, [openagentic_workflow_dsl_utils:err(Path, <<"not_object">>, <<"on_decision must be an object">>) | Errors0]}.

validate_on_decision_entries(_Path, [], Errors) -> Errors;
validate_on_decision_entries(Path, [{K0, V0} | Rest], Errors0) ->
  K = openagentic_workflow_dsl_utils:to_bin(K0),
  Errors1 = case byte_size(string:trim(K)) > 0 of true -> Errors0; false -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".<key>">>]), <<"missing">>, <<"on_decision keys must be non-empty strings">>) | Errors0] end,
  Errors2 =
    case V0 of
      null -> Errors1;
      undefined -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".">>, K]), <<"missing">>, <<"on_decision values must be a step id or null">>) | Errors1];
      B when is_binary(B) -> openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".">>, K]), B, <<"step id is required">>, Errors1);
      _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".">>, K]), <<"invalid_type">>, <<"on_decision values must be a string or null">>) | Errors1]
    end,
  validate_on_decision_entries(Path, Rest, Errors2).

validate_on_decision_refs(_Path, Map0, _StepIdSet, Errors) when Map0 =:= undefined; Map0 =:= null -> Errors;
validate_on_decision_refs(Path, Map0, StepIdSet, Errors0) ->
  Map = openagentic_workflow_dsl_utils:ensure_map(Map0),
  lists:foldl(
    fun ({K0, V0}, Acc0) ->
      K = openagentic_workflow_dsl_utils:to_bin(K0),
      case V0 of
        null -> Acc0;
        undefined -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".">>, K]), <<"missing">>, <<"step ref is required (or null)">>) | Acc0];
        Ref when is_binary(Ref) -> openagentic_workflow_dsl_transitions:validate_step_ref(iolist_to_binary([Path, <<".">>, K]), Ref, StepIdSet, Acc0);
        _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".">>, K]), <<"invalid_type">>, <<"step ref must be a string or null">>) | Acc0]
      end
    end,
    Errors0,
    maps:to_list(Map)
  ).
