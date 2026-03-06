-module(openagentic_workflow_dsl).

-export([
  load/3,
  load_and_validate/3,
  validate/3
]).

%% Workflow DSL loader + validator (v1).
%%
%% Goals:
%% - Fail-fast: invalid DSL should not start a workflow.
%% - Keep schema cross-language friendly (JSON maps/lists/binaries).
%% - Avoid dynamic atoms (keys handled as binaries or known atoms).

load(ProjectDir0, RelPath0, Opts0) ->
  ProjectDir = ensure_list(ProjectDir0),
  RelPath = ensure_list(RelPath0),
  _Opts = ensure_map(Opts0),
  case openagentic_fs:resolve_project_path(ProjectDir, RelPath) of
    {ok, AbsPath} ->
      case file:read_file(AbsPath) of
        {ok, Bin} ->
          try
            Obj = openagentic_json:decode(Bin),
            case is_map(Obj) of
              true -> {ok, Obj};
              false -> {error, {invalid_workflow_dsl, [err(<<"$">>, <<"not_object">>, <<"workflow must be a JSON object">>)]}}
            end
          catch
            _:_ ->
              {error, {invalid_workflow_dsl, [err(<<"$">>, <<"invalid_json">>, <<"workflow must be valid JSON">>)]}}
          end;
        {error, Reason} ->
          {error, {invalid_workflow_dsl, [err(<<"$">>, <<"read_failed">>, to_bin(io_lib:format("read failed: ~p", [Reason])))]}}
      end;
    {error, unsafe_path} ->
      {error, {invalid_workflow_dsl, [err(<<"$">>, <<"unsafe_path">>, <<"workflow path is unsafe">>)]}}
  end.

load_and_validate(ProjectDir0, RelPath0, Opts0) ->
  ProjectDir = ensure_list(ProjectDir0),
  RelPath = ensure_list(RelPath0),
  Opts = ensure_map(Opts0),
  case load(ProjectDir, RelPath, Opts) of
    {ok, Wf} ->
      validate(ProjectDir, Wf, Opts);
    Err ->
      Err
  end.

validate(ProjectDir0, Workflow0, Opts0) ->
  ProjectDir = ensure_list(ProjectDir0),
  Workflow = ensure_map(Workflow0),
  Opts = ensure_map(Opts0),
  StrictUnknown = to_bool_default(maps:get(strict_unknown_fields, Opts, true), true),
  Errors0 = [],

  AllowedTop = [<<"workflow_version">>, <<"name">>, <<"description">>, <<"roles">>, <<"defaults">>, <<"steps">>],
  Errors1 = maybe_only_keys(StrictUnknown, Workflow, AllowedTop, <<"$">>, Errors0),

  WfVer = get_bin(Workflow, [<<"workflow_version">>, workflow_version], <<>>),
  Errors2 =
    case WfVer of
      <<"1.0">> -> Errors1;
      <<>> -> [err(<<"workflow_version">>, <<"missing">>, <<"workflow_version is required">>) | Errors1];
      _ -> [err(<<"workflow_version">>, <<"unsupported_version">>, iolist_to_binary([<<"unsupported workflow_version: ">>, WfVer])) | Errors1]
    end,

  Name = get_bin(Workflow, [<<"name">>, name], <<>>),
  Errors3 = require_nonempty_bin(<<"name">>, Name, <<"name is required">>, Errors2),

  Steps0 = get_any(Workflow, [<<"steps">>, steps], undefined),
  {Steps, Errors4} = require_list(<<"steps">>, Steps0, <<"steps must be an array">>, Errors3),
  Errors5 =
    case Steps of
      [] -> [err(<<"steps">>, <<"empty">>, <<"steps must be non-empty">>) | Errors4];
      _ -> Errors4
    end,

  {StepInfos, Errors6} = validate_steps(ProjectDir, Steps, StrictUnknown, Errors5),
  StepIds = [Id || #{id := Id} <- StepInfos],
  StepIdSet = maps:from_list([{Id, true} || Id <- StepIds]),
  Errors7 = validate_transitions(StepInfos, StepIdSet, Errors6),
  Errors8 = validate_terminal_path(StepInfos, StepIdSet, Errors7),

  ErrorsSorted = sort_errors(Errors8),
  case ErrorsSorted of
    [] ->
      %% Return a normalized map (keys as binaries where possible) for engine use.
      Norm = normalize_workflow(Workflow, StepInfos),
      {ok, Norm};
    _ ->
      {error, {invalid_workflow_dsl, ErrorsSorted}}
  end.

%% ---- validation helpers ----

validate_steps(ProjectDir, Steps, StrictUnknown, Errors0) ->
  validate_steps(ProjectDir, Steps, StrictUnknown, 0, #{}, [], Errors0).

validate_steps(_ProjectDir, [], _StrictUnknown, _Idx, _Seen, AccInfosRev, Errors) ->
  {lists:reverse(AccInfosRev), Errors};
validate_steps(ProjectDir, [S0 | Rest], StrictUnknown, Idx, Seen0, AccInfosRev, Errors0) ->
  Path0 = iolist_to_binary([<<"steps[">>, integer_to_binary(Idx), <<"]">>]),
  S = ensure_map(S0),
  AllowedStep = [
    <<"id">>,
    <<"role">>,
    <<"input">>,
    <<"prompt">>,
    <<"output_contract">>,
    <<"guards">>,
    <<"on_pass">>,
    <<"on_fail">>,
    <<"on_decision">>,
    <<"max_attempts">>,
    <<"timeout_seconds">>,
    <<"tool_policy">>,
    <<"retry_policy">>,
    <<"executor">>,
    <<"fanout">>
  ],
  Errors1 = maybe_only_keys(StrictUnknown, S, AllowedStep, Path0, Errors0),

  Id = get_bin(S, [<<"id">>, id], <<>>),
  Errors2 = require_nonempty_bin(iolist_to_binary([Path0, <<".id">>]), Id, <<"step id is required">>, Errors1),
  Errors3 =
    case is_safe_step_id(Id) of
      true -> Errors2;
      false when Id =:= <<>> -> Errors2;
      false -> [err(iolist_to_binary([Path0, <<".id">>]), <<"invalid_id">>, <<"step id must match [a-z0-9_]+">>) | Errors2]
    end,

  Errors4 =
    case {Id =/= <<>>, maps:get(Id, Seen0, false)} of
      {true, true} -> [err(iolist_to_binary([Path0, <<".id">>]), <<"duplicate_id">>, <<"duplicate step id">>) | Errors3];
      _ -> Errors3
    end,
  Seen = case Id =:= <<>> of true -> Seen0; false -> Seen0#{Id => true} end,

  Role = get_bin(S, [<<"role">>, role], <<>>),
  Errors5 = require_nonempty_bin(iolist_to_binary([Path0, <<".role">>]), Role, <<"role is required">>, Errors4),

  Exec = get_bin(S, [<<"executor">>, executor], <<>>),
  IsFanoutJoin = Exec =:= <<"fanout_join">>,

  Errors6 =
    case Exec of
      <<>> -> Errors5;
      <<"local_otp">> -> Errors5;
      <<"fanout_join">> -> Errors5;
      <<"http_sse_remote">> -> [err(iolist_to_binary([Path0, <<".executor">>]), <<"unsupported_executor">>, <<"http_sse_remote is reserved for future">>) | Errors5];
      _ -> [err(iolist_to_binary([Path0, <<".executor">>]), <<"unknown_executor">>, <<"unknown executor">>) | Errors5]
    end,

  {Input, Errors7} =
    case IsFanoutJoin of
      true -> {#{}, Errors6};
      false -> require_map(iolist_to_binary([Path0, <<".input">>]), get_any(S, [<<"input">>, input], undefined), <<"input is required">>, Errors6)
    end,
  Errors8 =
    case IsFanoutJoin of
      true -> Errors7;
      false -> validate_input_binding(iolist_to_binary([Path0, <<".input">>]), Input, Errors7)
    end,

  {Prompt, Errors9} =
    case IsFanoutJoin of
      true -> {#{}, Errors8};
      false -> require_map(iolist_to_binary([Path0, <<".prompt">>]), get_any(S, [<<"prompt">>, prompt], undefined), <<"prompt is required">>, Errors8)
    end,
  Errors10 =
    case IsFanoutJoin of
      true -> Errors9;
      false -> validate_prompt_ref(ProjectDir, iolist_to_binary([Path0, <<".prompt">>]), Prompt, Errors9)
    end,

  {OutC, Errors11} =
    case IsFanoutJoin of
      true -> {#{}, Errors10};
      false -> require_map(iolist_to_binary([Path0, <<".output_contract">>]), get_any(S, [<<"output_contract">>, output_contract], undefined), <<"output_contract is required">>, Errors10)
    end,
  Errors12 =
    case IsFanoutJoin of
      true -> Errors11;
      false -> validate_output_contract(iolist_to_binary([Path0, <<".output_contract">>]), OutC, Errors11)
    end,

  Guards0 = get_any(S, [<<"guards">>, guards], []),
  Guards = case is_list(Guards0) of true -> Guards0; false -> [] end,
  Errors13 =
    case {IsFanoutJoin, is_list(Guards0)} of
      {true, _} -> Errors12;
      {false, true} -> Errors12;
      {false, false} -> [err(iolist_to_binary([Path0, <<".guards">>]), <<"not_array">>, <<"guards must be an array">>) | Errors12]
    end,
  Errors14 =
    case IsFanoutJoin of
      true -> Errors13;
      false -> validate_guards(iolist_to_binary([Path0, <<".guards">>]), Guards, Errors13)
    end,

  OnPass0 = get_nullable_step_ref(S, [<<"on_pass">>, on_pass]),
  OnPass =
    case {IsFanoutJoin, OnPass0} of
      {true, undefined} -> null;
      _ -> OnPass0
    end,
  OnFail = get_nullable_step_ref(S, [<<"on_fail">>, on_fail]),
  OnDecision0 = get_any(S, [<<"on_decision">>, on_decision], undefined),
  {OnDecision, Errors15} = validate_on_decision(iolist_to_binary([Path0, <<".on_decision">>]), OnDecision0, Errors14),
  RetryPolicy0 = get_any(S, [<<"retry_policy">>, retry_policy], undefined),
  {RetryPolicy, Errors16} = validate_retry_policy(iolist_to_binary([Path0, <<".retry_policy">>]), RetryPolicy0, StrictUnknown, Errors15),

  {FanoutSteps, Join, Errors17} =
    case IsFanoutJoin of
      true -> validate_fanout(iolist_to_binary([Path0, <<".fanout">>]), get_any(S, [<<"fanout">>, fanout], undefined), Errors16);
      false -> {[], null, Errors16}
    end,

  Raw1 = normalize_retry_policy_raw(S, RetryPolicy),
  Info = #{id => Id, role => Role, executor => Exec, on_pass => OnPass, on_fail => OnFail, on_decision => OnDecision, retry_policy => RetryPolicy, fanout_steps => FanoutSteps, join => Join, raw => Raw1},
  validate_steps(ProjectDir, Rest, StrictUnknown, Idx + 1, Seen, [Info | AccInfosRev], Errors17).

validate_transitions(StepInfos, StepIdSet, Errors0) ->
  lists:foldl(
    fun (#{id := Id, executor := Exec, on_pass := OnPass, on_fail := OnFail, on_decision := OnDecision, fanout_steps := FanoutSteps, join := Join, raw := _Raw}, Acc) ->
      Acc1 =
        case Exec of
          <<"fanout_join">> -> Acc;
          _ -> validate_step_ref(iolist_to_binary([<<"steps.">>, Id, <<".on_pass">>]), OnPass, StepIdSet, Acc)
        end,
      Acc2 = validate_step_ref(iolist_to_binary([<<"steps.">>, Id, <<".on_fail">>]), OnFail, StepIdSet, Acc1),
      Acc3 = validate_on_decision_refs(iolist_to_binary([<<"steps.">>, Id, <<".on_decision">>]), OnDecision, StepIdSet, Acc2),
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
        false -> [err(<<"$">>, <<"no_terminal">>, <<"no terminal step reachable from start">>) | Errors0]
      end
  end.

reachable_steps(StartId, StepInfos, StepIdSet, Visited0) ->
  case maps:get(StartId, Visited0, false) of
    true ->
      Visited0;
    false ->
      Visited1 = Visited0#{StartId => true},
      Step = find_step(StartId, StepInfos),
      case Step of
        undefined ->
          Visited1;
        #{on_pass := OnPass, on_fail := OnFail, on_decision := OnDecision, fanout_steps := FanoutSteps, join := Join} ->
          Visited2 = follow_ref(OnPass, StepInfos, StepIdSet, Visited1),
          Visited3 = follow_ref(OnFail, StepInfos, StepIdSet, Visited2),
          Visited4 = follow_refs_in_map(OnDecision, StepInfos, StepIdSet, Visited3),
          Visited5 = follow_refs_in_list(FanoutSteps, StepInfos, StepIdSet, Visited4),
          follow_ref(Join, StepInfos, StepIdSet, Visited5)
      end
  end.

follow_refs_in_list([], _StepInfos, _StepIdSet, Visited0) ->
  Visited0;
follow_refs_in_list([Ref | Rest], StepInfos, StepIdSet, Visited0) ->
  follow_refs_in_list(Rest, StepInfos, StepIdSet, follow_ref(Ref, StepInfos, StepIdSet, Visited0)).

follow_refs_in_map(Map0, StepInfos, StepIdSet, Visited0) ->
  Map = ensure_map(Map0),
  lists:foldl(
    fun ({_K, V}, Acc) -> follow_ref(V, StepInfos, StepIdSet, Acc) end,
    Visited0,
    maps:to_list(Map)
  ).

follow_ref(null, _StepInfos, _StepIdSet, Visited) -> Visited;
follow_ref(undefined, _StepInfos, _StepIdSet, Visited) -> Visited;
follow_ref(Ref, StepInfos, StepIdSet, Visited) when is_binary(Ref) ->
  case maps:get(Ref, StepIdSet, false) of
    true -> reachable_steps(Ref, StepInfos, StepIdSet, Visited);
    false -> Visited
  end;
follow_ref(_Other, _StepInfos, _StepIdSet, Visited) ->
  Visited.

find_step(_Id, []) -> undefined;
find_step(Id, [#{id := Id} = S | _]) -> S;
find_step(Id, [_ | Rest]) -> find_step(Id, Rest).

validate_step_ref(_Path, null, _StepIdSet, Errors) ->
  Errors;
validate_step_ref(Path, Ref, StepIdSet, Errors) when is_binary(Ref) ->
  case maps:get(Ref, StepIdSet, false) of
    true -> Errors;
    false -> [err(Path, <<"unknown_step">>, iolist_to_binary([<<"unknown step: ">>, Ref])) | Errors]
  end;
validate_step_ref(Path, undefined, _StepIdSet, Errors) ->
  [err(Path, <<"missing">>, <<"step ref is required (or null)">>) | Errors];
validate_step_ref(Path, _Other, _StepIdSet, Errors) ->
  [err(Path, <<"invalid_type">>, <<"step ref must be a string or null">>) | Errors].

validate_step_refs(_Path, [], _StepIdSet, Errors) ->
  Errors;
validate_step_refs(Path, Refs, StepIdSet, Errors0) when is_list(Refs) ->
  lists:foldl(
    fun (Ref, Acc) ->
      validate_step_ref(Path, Ref, StepIdSet, Acc)
    end,
    Errors0,
    Refs
  );
validate_step_refs(Path, _Other, _StepIdSet, Errors) ->
  [err(Path, <<"invalid_type">>, <<"step refs must be an array">>) | Errors].

validate_fanout(Path, Fanout0, Errors0) ->
  {Fanout, Errors1} = require_map(Path, Fanout0, <<"fanout is required">>, Errors0),
  Steps0 = get_any(Fanout, [<<"steps">>, steps], undefined),
  {Steps, Errors2} = require_list(iolist_to_binary([Path, <<".steps">>]), Steps0, <<"fanout.steps must be an array">>, Errors1),
  Errors3 =
    case Steps of
      [] -> [err(iolist_to_binary([Path, <<".steps">>]), <<"empty">>, <<"fanout.steps must be non-empty">>) | Errors2];
      _ -> Errors2
    end,
  FanoutSteps = [to_bin(StepId) || StepId <- Steps],
  Errors4 =
    case lists:all(fun is_binary/1, FanoutSteps) of
      true -> Errors3;
      false -> [err(iolist_to_binary([Path, <<".steps">>]), <<"invalid_type">>, <<"fanout.steps must contain strings">>) | Errors3]
    end,
  Join = get_nullable_step_ref(Fanout, [<<"join">>, join]),
  Errors5 =
    case Join of
      undefined -> [err(iolist_to_binary([Path, <<".join">>]), <<"missing">>, <<"fanout.join is required">>) | Errors4];
      _ -> Errors4
    end,
  _MaxConcurrency = get_any(Fanout, [<<"max_concurrency">>, max_concurrency], undefined),
  _FailFast = get_any(Fanout, [<<"fail_fast">>, fail_fast], undefined),
  {FanoutSteps, Join, Errors5}.

validate_input_binding(Path, Input, Errors0) ->
  T = get_bin(Input, [<<"type">>, type], <<>>),
  case T of
    <<"controller_input">> ->
      Errors0;
    <<"step_output">> ->
      StepId = get_bin(Input, [<<"step_id">>, step_id], <<>>),
      require_nonempty_bin(iolist_to_binary([Path, <<".step_id">>]), StepId, <<"step_id is required">>, Errors0);
    <<"merge">> ->
      Sources0 = get_any(Input, [<<"sources">>, sources], undefined),
      {Sources, Errors1} = require_list(iolist_to_binary([Path, <<".sources">>]), Sources0, <<"sources must be an array">>, Errors0),
      case Sources of
        [] -> [err(iolist_to_binary([Path, <<".sources">>]), <<"empty">>, <<"sources must be non-empty">>) | Errors1];
        _ -> Errors1
      end;
    <<>> ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"input.type is required">>) | Errors0];
    _ ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"unknown_input_type">>, iolist_to_binary([<<"unknown input type: ">>, T])) | Errors0]
  end.

validate_prompt_ref(ProjectDir, Path, Prompt, Errors0) ->
  T = get_bin(Prompt, [<<"type">>, type], <<>>),
  case T of
    <<"inline">> ->
      Txt = get_bin(Prompt, [<<"text">>, text], <<>>),
      require_nonempty_bin(iolist_to_binary([Path, <<".text">>]), Txt, <<"prompt.text is required">>, Errors0);
    <<"file">> ->
      P = get_bin(Prompt, [<<"path">>, path], <<>>),
      Errors1 = require_nonempty_bin(iolist_to_binary([Path, <<".path">>]), P, <<"prompt.path is required">>, Errors0),
      case P of
        <<>> ->
          Errors1;
        _ ->
          case openagentic_fs:resolve_project_path(ProjectDir, P) of
            {ok, Abs} ->
              case filelib:is_file(Abs) of
                true -> Errors1;
                false -> [err(iolist_to_binary([Path, <<".path">>]), <<"missing_file">>, <<"prompt file does not exist">>) | Errors1]
              end;
            {error, unsafe_path} ->
              [err(iolist_to_binary([Path, <<".path">>]), <<"unsafe_path">>, <<"prompt path is unsafe">>) | Errors1]
          end
      end;
    <<>> ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"prompt.type is required">>) | Errors0];
    _ ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"unknown_prompt_type">>, iolist_to_binary([<<"unknown prompt type: ">>, T])) | Errors0]
  end.

validate_output_contract(Path, OutC, Errors0) ->
  T = get_bin(OutC, [<<"type">>, type], <<>>),
  case T of
    <<"markdown_sections">> ->
      Req0 = get_any(OutC, [<<"required">>, required], undefined),
      {Req, Errors1} = require_list(iolist_to_binary([Path, <<".required">>]), Req0, <<"required must be an array">>, Errors0),
      case Req of
        [] -> [err(iolist_to_binary([Path, <<".required">>]), <<"empty">>, <<"required must be non-empty">>) | Errors1];
        _ -> Errors1
      end;
    <<"decision">> ->
      Allowed0 = get_any(OutC, [<<"allowed">>, allowed], undefined),
      {_Allowed, Errors1} = require_list(iolist_to_binary([Path, <<".allowed">>]), Allowed0, <<"allowed must be an array">>, Errors0),
      Fmt = get_bin(OutC, [<<"format">>, format], <<>>),
      Errors2 =
        case Fmt of
          <<>> -> Errors1;
          <<"json">> -> Errors1;
          _ -> [err(iolist_to_binary([Path, <<".format">>]), <<"invalid_format">>, <<"decision.format must be json">>) | Errors1]
        end,
      Fields0 = get_any(OutC, [<<"fields">>, fields], undefined),
      {_Fields, Errors3} = require_list(iolist_to_binary([Path, <<".fields">>]), Fields0, <<"fields must be an array">>, Errors2),
      Errors3;
    <<"json_object">> ->
      Errors0;
    <<>> ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"output_contract.type is required">>) | Errors0];
    _ ->
      [err(iolist_to_binary([Path, <<".type">>]), <<"unknown_output_contract_type">>, iolist_to_binary([<<"unknown output_contract type: ">>, T])) | Errors0]
  end.

validate_guards(Path0, Guards, Errors0) ->
  validate_guards(Path0, Guards, 0, Errors0).

validate_guards(_Path0, [], _Idx, Errors) ->
  Errors;
validate_guards(Path0, [G0 | Rest], Idx, Errors0) ->
  Path = iolist_to_binary([Path0, <<"[">>, integer_to_binary(Idx), <<"]">>]),
  G = ensure_map(G0),
  T = get_bin(G, [<<"type">>, type], <<>>),
  Errors1 =
    case T of
      <<"max_words">> ->
        Errors0;
      <<"regex_must_match">> ->
        P = get_bin(G, [<<"pattern">>, pattern], <<>>),
        require_nonempty_bin(iolist_to_binary([Path, <<".pattern">>]), P, <<"pattern is required">>, Errors0);
      <<"markdown_sections">> ->
        Req0 = get_any(G, [<<"required">>, required], undefined),
        {_Req, ErrorsX} = require_list(iolist_to_binary([Path, <<".required">>]), Req0, <<"required must be an array">>, Errors0),
        ErrorsX;
      <<"decision_requires_reasons">> ->
        W = get_bin(G, [<<"when">>, 'when'], <<>>),
        require_nonempty_bin(iolist_to_binary([Path, <<".when">>]), W, <<"when is required">>, Errors0);
      <<"requires_evidence">> ->
        Cmds0 = get_any(G, [<<"commands">>, commands], undefined),
        {_Cmds, ErrorsX} = require_list(iolist_to_binary([Path, <<".commands">>]), Cmds0, <<"commands must be an array">>, Errors0),
        ErrorsX;
      <<>> ->
        [err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"guard.type is required">>) | Errors0];
      _ ->
        [err(iolist_to_binary([Path, <<".type">>]), <<"unknown_guard_type">>, iolist_to_binary([<<"unknown guard type: ">>, T])) | Errors0]
    end,
  validate_guards(Path0, Rest, Idx + 1, Errors1).

validate_on_decision(_Path, undefined, Errors) ->
  {#{}, Errors};
validate_on_decision(_Path, null, Errors) ->
  {#{}, Errors};
validate_on_decision(Path, M0, Errors0) when is_map(M0) ->
  {M0, validate_on_decision_entries(Path, maps:to_list(M0), Errors0)};
validate_on_decision(Path, L0, Errors0) when is_list(L0) ->
  try
    M = maps:from_list(L0),
    {M, validate_on_decision_entries(Path, maps:to_list(M), Errors0)}
  catch
    _:_ ->
      {#{}, [err(Path, <<"not_object">>, <<"on_decision must be an object">>) | Errors0]}
  end;
validate_on_decision(Path, _Other, Errors0) ->
  {#{}, [err(Path, <<"not_object">>, <<"on_decision must be an object">>) | Errors0]}.

validate_on_decision_entries(_Path, [], Errors) ->
  Errors;
validate_on_decision_entries(Path, [{K0, V0} | Rest], Errors0) ->
  K = to_bin(K0),
  V = V0,
  Errors1 =
    case byte_size(string:trim(K)) > 0 of
      true -> Errors0;
      false -> [err(iolist_to_binary([Path, <<".<key>">>]), <<"missing">>, <<"on_decision keys must be non-empty strings">>) | Errors0]
    end,
  Errors2 =
    case V of
      null -> Errors1;
      undefined -> [err(iolist_to_binary([Path, <<".">>, K]), <<"missing">>, <<"on_decision values must be a step id or null">>) | Errors1];
      B when is_binary(B) -> require_nonempty_bin(iolist_to_binary([Path, <<".">>, K]), B, <<"step id is required">>, Errors1);
      _ -> [err(iolist_to_binary([Path, <<".">>, K]), <<"invalid_type">>, <<"on_decision values must be a string or null">>) | Errors1]
    end,
  validate_on_decision_entries(Path, Rest, Errors2).

validate_on_decision_refs(_Path, Map0, _StepIdSet, Errors) when Map0 =:= undefined; Map0 =:= null ->
  Errors;
validate_on_decision_refs(Path, Map0, StepIdSet, Errors0) ->
  Map = ensure_map(Map0),
  lists:foldl(
    fun ({K0, V0}, Acc0) ->
      K = to_bin(K0),
      case V0 of
        null -> Acc0;
        undefined -> [err(iolist_to_binary([Path, <<".">>, K]), <<"missing">>, <<"step ref is required (or null)">>) | Acc0];
        Ref when is_binary(Ref) ->
          validate_step_ref(iolist_to_binary([Path, <<".">>, K]), Ref, StepIdSet, Acc0);
        _ ->
          [err(iolist_to_binary([Path, <<".">>, K]), <<"invalid_type">>, <<"step ref must be a string or null">>) | Acc0]
      end
    end,
    Errors0,
    maps:to_list(Map)
  ).

validate_retry_policy(_Path, undefined, _StrictUnknown, Errors) ->
  {undefined, Errors};
validate_retry_policy(_Path, null, _StrictUnknown, Errors) ->
  {undefined, Errors};
validate_retry_policy(Path, Retry0, StrictUnknown, Errors0) ->
  {Retry, Errors1} = require_map(Path, Retry0, <<"retry_policy must be an object">>, Errors0),
  Allowed = [<<"transient_provider_errors">>, <<"max_retries">>, <<"backoff_ms">>],
  Errors2 = maybe_only_keys(StrictUnknown, Retry, Allowed, Path, Errors1),
  {TransientProviderErrors, Errors3} =
    case get_any(Retry, [<<"transient_provider_errors">>, transient_provider_errors], undefined) of
      undefined -> {false, Errors2};
      true -> {true, Errors2};
      false -> {false, Errors2};
      _ ->
        {false, [err(iolist_to_binary([Path, <<".transient_provider_errors">>]), <<"invalid_type">>, <<"transient_provider_errors must be a boolean">>) | Errors2]}
    end,
  {MaxRetries, Errors4} =
    validate_retry_int(
      iolist_to_binary([Path, <<".max_retries">>]),
      get_any(Retry, [<<"max_retries">>, max_retries], undefined),
      0,
      0,
      3,
      <<"max_retries must be an integer between 0 and 3">>,
      Errors3
    ),
  {BackoffMs, Errors5} =
    validate_retry_int(
      iolist_to_binary([Path, <<".backoff_ms">>]),
      get_any(Retry, [<<"backoff_ms">>, backoff_ms], undefined),
      1000,
      1,
      30000,
      <<"backoff_ms must be an integer between 1 and 30000">>,
      Errors4
    ),
  {#{<<"transient_provider_errors">> => TransientProviderErrors, <<"max_retries">> => MaxRetries, <<"backoff_ms">> => BackoffMs}, Errors5}.

validate_retry_int(_Path, undefined, Default, _Min, _Max, _Msg, Errors) ->
  {Default, Errors};
validate_retry_int(_Path, Value, _Default, Min, Max, _Msg, Errors) when is_integer(Value), Value >= Min, Value =< Max ->
  {Value, Errors};
validate_retry_int(Path, Value, Default, _Min, _Max, Msg, Errors) when is_integer(Value) ->
  {Default, [err(Path, <<"out_of_range">>, Msg) | Errors]};
validate_retry_int(Path, _Value, Default, _Min, _Max, Msg, Errors) ->
  {Default, [err(Path, <<"invalid_type">>, Msg) | Errors]}.

%% ---- normalization ----

normalize_workflow(Workflow, StepInfos) ->
  %% Keep original object but inject a stable index and normalized fields for engine use.
  StepsById = maps:from_list([{Id, Raw} || #{id := Id, raw := Raw} <- StepInfos, Id =/= <<>>]),
  Workflow#{
    <<"steps_by_id">> => StepsById,
    <<"start_step_id">> =>
      case StepInfos of
        [#{id := Id} | _] -> Id;
        _ -> <<>>
      end
  }.

normalize_retry_policy_raw(StepRaw, undefined) ->
  StepRaw;
normalize_retry_policy_raw(StepRaw, RetryPolicy) ->
  StepRaw#{<<"retry_policy">> => RetryPolicy}.

%% ---- generic helpers ----

maybe_only_keys(false, _Map, _Allowed, _Path, Errors) ->
  Errors;
maybe_only_keys(true, Map, Allowed, Path, Errors0) ->
  Keys = maps:keys(Map),
  Unknown = [K || K <- Keys, is_binary(K), not lists:member(K, Allowed)],
  case Unknown of
    [] ->
      Errors0;
    _ ->
      Msg = iolist_to_binary([<<"unknown keys: ">>, join_binaries(Unknown, <<", ">>)]),
      [err(Path, <<"unknown_keys">>, Msg) | Errors0]
  end.

join_binaries([], _Sep) -> <<>>;
join_binaries([B], _Sep) -> B;
join_binaries([B | Rest], Sep) ->
  iolist_to_binary([B, Sep, join_binaries(Rest, Sep)]).

get_any(Map, Keys, Default) ->
  get_any_loop(Map, Keys, Default).

get_any_loop(_Map, [], Default) ->
  Default;
get_any_loop(Map, [K | Rest], Default) ->
  case maps:find(K, Map) of
    {ok, V} -> V;
    error -> get_any_loop(Map, Rest, Default)
  end.

get_bin(Map, Keys, Default) ->
  V = get_any(Map, Keys, Default),
  case V of
    B when is_binary(B) -> B;
    L when is_list(L) -> iolist_to_binary(L);
    A when is_atom(A) -> atom_to_binary(A, utf8);
    I when is_integer(I) -> integer_to_binary(I);
    null -> <<>>;
    undefined -> <<>>;
    _ -> Default
  end.

get_nullable_step_ref(Map, Keys) ->
  V = get_any(Map, Keys, undefined),
  case V of
    null -> null;
    undefined -> undefined;
    B when is_binary(B) -> string:trim(B);
    L when is_list(L) -> string:trim(iolist_to_binary(L));
    A when is_atom(A) ->
      case A of
        null -> null;
        _ -> atom_to_binary(A, utf8)
      end;
    _ -> undefined
  end.

require_list(_Path, V, _Msg, Errors) when is_list(V) ->
  {V, Errors};
require_list(Path, _V, Msg, Errors) ->
  {[], [err(Path, <<"invalid_type">>, Msg) | Errors]}.

require_map(_Path, V, _Msg, Errors) when is_map(V) ->
  {V, Errors};
require_map(Path, _V, Msg, Errors) ->
  {#{}, [err(Path, <<"invalid_type">>, Msg) | Errors]}.

require_nonempty_bin(_Path, Bin, _Msg, Errors) when is_binary(Bin), byte_size(Bin) > 0 ->
  Errors;
require_nonempty_bin(Path, _Bin, Msg, Errors) ->
  [err(Path, <<"missing">>, Msg) | Errors].

is_safe_step_id(<<>>) -> false;
is_safe_step_id(Id) when is_binary(Id) ->
  case re:run(Id, <<"^[a-z0-9_]+$">>, [{capture, none}]) of
    match -> true;
    _ -> false
  end;
is_safe_step_id(_) ->
  false.

err(Path0, Code0, Msg0) ->
  #{path => to_bin(Path0), code => to_bin(Code0), message => to_bin(Msg0)}.

sort_errors(Errors) ->
  lists:sort(
    fun (A, B) ->
      maps:get(path, A, <<>>) =< maps:get(path, B, <<>>)
    end,
    Errors
  ).

to_bool_default(V0, Default) ->
  case V0 of
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    <<"1">> -> true;
    <<"0">> -> false;
    1 -> true;
    0 -> false;
    _ -> Default
  end.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
