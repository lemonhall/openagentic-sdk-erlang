-module(openagentic_workflow_dsl_steps).
-export([validate_steps/4]).

validate_steps(ProjectDir, Steps, StrictUnknown, Errors0) ->
  validate_steps(ProjectDir, Steps, StrictUnknown, 0, #{}, [], Errors0).

validate_steps(_ProjectDir, [], _StrictUnknown, _Idx, _Seen, AccInfosRev, Errors) ->
  {lists:reverse(AccInfosRev), Errors};
validate_steps(ProjectDir, [S0 | Rest], StrictUnknown, Idx, Seen0, AccInfosRev, Errors0) ->
  Path0 = iolist_to_binary([<<"steps[">>, integer_to_binary(Idx), <<"]">>]),
  S = openagentic_workflow_dsl_utils:ensure_map(S0),
  AllowedStep = [<<"id">>, <<"role">>, <<"input">>, <<"prompt">>, <<"output_contract">>, <<"guards">>, <<"on_pass">>, <<"on_fail">>, <<"on_decision">>, <<"max_attempts">>, <<"timeout_seconds">>, <<"tool_policy">>, <<"retry_policy">>, <<"executor">>, <<"fanout">>],
  Errors1 = openagentic_workflow_dsl_utils:maybe_only_keys(StrictUnknown, S, AllowedStep, Path0, Errors0),
  Id = openagentic_workflow_dsl_utils:get_bin(S, [<<"id">>, id], <<>>),
  Errors2 = openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path0, <<".id">>]), Id, <<"step id is required">>, Errors1),
  Errors3 =
    case openagentic_workflow_dsl_utils:is_safe_step_id(Id) of
      true -> Errors2;
      false when Id =:= <<>> -> Errors2;
      false -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path0, <<".id">>]), <<"invalid_id">>, <<"step id must match [a-z0-9_]+">>) | Errors2]
    end,
  Errors4 =
    case {Id =/= <<>>, maps:get(Id, Seen0, false)} of
      {true, true} -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path0, <<".id">>]), <<"duplicate_id">>, <<"duplicate step id">>) | Errors3];
      _ -> Errors3
    end,
  Seen = case Id =:= <<>> of true -> Seen0; false -> Seen0#{Id => true} end,
  Role = openagentic_workflow_dsl_utils:get_bin(S, [<<"role">>, role], <<>>),
  Errors5 = openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path0, <<".role">>]), Role, <<"role is required">>, Errors4),
  Exec = openagentic_workflow_dsl_utils:get_bin(S, [<<"executor">>, executor], <<>>),
  IsFanoutJoin = Exec =:= <<"fanout_join">>,
  Errors6 =
    case Exec of
      <<>> -> Errors5;
      <<"local_otp">> -> Errors5;
      <<"fanout_join">> -> Errors5;
      <<"http_sse_remote">> -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path0, <<".executor">>]), <<"unsupported_executor">>, <<"http_sse_remote is reserved for future">>) | Errors5];
      _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path0, <<".executor">>]), <<"unknown_executor">>, <<"unknown executor">>) | Errors5]
    end,
  {Input, Errors7} =
    case IsFanoutJoin of
      true -> {#{}, Errors6};
      false -> openagentic_workflow_dsl_utils:require_map(iolist_to_binary([Path0, <<".input">>]), openagentic_workflow_dsl_utils:get_any(S, [<<"input">>, input], undefined), <<"input is required">>, Errors6)
    end,
  Errors8 = case IsFanoutJoin of true -> Errors7; false -> openagentic_workflow_dsl_step_fields:validate_input_binding(iolist_to_binary([Path0, <<".input">>]), Input, Errors7) end,
  {Prompt, Errors9} =
    case IsFanoutJoin of
      true -> {#{}, Errors8};
      false -> openagentic_workflow_dsl_utils:require_map(iolist_to_binary([Path0, <<".prompt">>]), openagentic_workflow_dsl_utils:get_any(S, [<<"prompt">>, prompt], undefined), <<"prompt is required">>, Errors8)
    end,
  Errors10 = case IsFanoutJoin of true -> Errors9; false -> openagentic_workflow_dsl_step_fields:validate_prompt_ref(ProjectDir, iolist_to_binary([Path0, <<".prompt">>]), Prompt, Errors9) end,
  {OutC, Errors11} =
    case IsFanoutJoin of
      true -> {#{}, Errors10};
      false -> openagentic_workflow_dsl_utils:require_map(iolist_to_binary([Path0, <<".output_contract">>]), openagentic_workflow_dsl_utils:get_any(S, [<<"output_contract">>, output_contract], undefined), <<"output_contract is required">>, Errors10)
    end,
  Errors12 = case IsFanoutJoin of true -> Errors11; false -> openagentic_workflow_dsl_step_fields:validate_output_contract(iolist_to_binary([Path0, <<".output_contract">>]), OutC, Errors11) end,
  Guards0 = openagentic_workflow_dsl_utils:get_any(S, [<<"guards">>, guards], []),
  Guards = case is_list(Guards0) of true -> Guards0; false -> [] end,
  Errors13 =
    case {IsFanoutJoin, is_list(Guards0)} of
      {true, _} -> Errors12;
      {false, true} -> Errors12;
      {false, false} -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path0, <<".guards">>]), <<"not_array">>, <<"guards must be an array">>) | Errors12]
    end,
  Errors14 = case IsFanoutJoin of true -> Errors13; false -> openagentic_workflow_dsl_guards:validate_guards(iolist_to_binary([Path0, <<".guards">>]), Guards, Errors13) end,
  OnPass0 = openagentic_workflow_dsl_utils:get_nullable_step_ref(S, [<<"on_pass">>, on_pass]),
  OnPass = case {IsFanoutJoin, OnPass0} of {true, undefined} -> null; _ -> OnPass0 end,
  OnFail = openagentic_workflow_dsl_utils:get_nullable_step_ref(S, [<<"on_fail">>, on_fail]),
  OnDecision0 = openagentic_workflow_dsl_utils:get_any(S, [<<"on_decision">>, on_decision], undefined),
  {OnDecision, Errors15} = openagentic_workflow_dsl_guards:validate_on_decision(iolist_to_binary([Path0, <<".on_decision">>]), OnDecision0, Errors14),
  RetryPolicy0 = openagentic_workflow_dsl_utils:get_any(S, [<<"retry_policy">>, retry_policy], undefined),
  {RetryPolicy, Errors16} = openagentic_workflow_dsl_retry:validate_retry_policy(iolist_to_binary([Path0, <<".retry_policy">>]), RetryPolicy0, StrictUnknown, Errors15),
  {FanoutSteps, Join, Errors17} =
    case IsFanoutJoin of
      true -> openagentic_workflow_dsl_step_fields:validate_fanout(iolist_to_binary([Path0, <<".fanout">>]), openagentic_workflow_dsl_utils:get_any(S, [<<"fanout">>, fanout], undefined), Errors16);
      false -> {[], null, Errors16}
    end,
  Raw1 = openagentic_workflow_dsl_retry:normalize_retry_policy_raw(S, RetryPolicy),
  Info = #{id => Id, role => Role, executor => Exec, on_pass => OnPass, on_fail => OnFail, on_decision => OnDecision, retry_policy => RetryPolicy, fanout_steps => FanoutSteps, join => Join, raw => Raw1},
  validate_steps(ProjectDir, Rest, StrictUnknown, Idx + 1, Seen, [Info | AccInfosRev], Errors17).
