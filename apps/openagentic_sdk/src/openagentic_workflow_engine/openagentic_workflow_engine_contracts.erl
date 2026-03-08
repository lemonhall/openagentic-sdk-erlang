-module(openagentic_workflow_engine_contracts).
-export([infer_output_format/1,eval_step_output/2,eval_output_contract/2,eval_guards/3,step_next/2]).

infer_output_format(StepRaw) ->
  OutC = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"decision">> -> <<"json">>;
    <<"json_object">> -> <<"json">>;
    _ -> <<"markdown">>
  end.

%% ---- evaluation ----

eval_step_output(StepRaw, Output0) ->
  Output = openagentic_workflow_engine_utils:to_bin(Output0),
  OutC = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  case eval_output_contract(OutC, Output) of
    {ok, Parsed} ->
      Guards = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"guards">>, guards], [])),
      case eval_guards(Guards, Output, Parsed) of
        ok -> {ok, Parsed};
        {error, Reasons} -> {error, Reasons}
      end;
    {error, Reasons} ->
      {error, Reasons}
  end.

eval_output_contract(OutC, Output) ->
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"markdown_sections">> ->
      Req = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(OutC, [<<"required">>, required], [])),
      case openagentic_workflow_engine_output_helpers:missing_sections(Req, Output) of
        [] -> {ok, #{type => markdown}};
        Missing ->
          {error, [iolist_to_binary([<<"missing sections: ">>, openagentic_workflow_engine_utils:join_bins([openagentic_workflow_engine_utils:to_bin(M) || M <- Missing], <<", ">>)])]}
      end;
    <<"decision">> ->
      case openagentic_workflow_engine_output_helpers:parse_json_object(Output) of
        {ok, Obj} ->
          Allowed = [openagentic_workflow_engine_utils:to_bin(X) || X <- openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(OutC, [<<"allowed">>, allowed], []))],
          Decision = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Obj, [<<"decision">>, decision], <<>>)),
          case lists:member(Decision, Allowed) of
            true -> {ok, Obj#{type => decision}};
            false -> {error, [<<"invalid decision">>]}
          end;
        {error, _} ->
          {error, [<<"decision output must be a JSON object">>]}
      end;
    <<"json_object">> ->
      case openagentic_workflow_engine_output_helpers:parse_json_object(Output) of
        {ok, Obj} -> {ok, Obj#{type => json_object}};
        {error, _} -> {error, [<<"output must be a JSON object">>]}
      end;
    _ ->
      {ok, #{type => unknown}}
  end.

eval_guards([], _Output, _Parsed) ->
  ok;
eval_guards([G0 | Rest], Output, Parsed) ->
  G = openagentic_workflow_engine_utils:ensure_map(G0),
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(G, [<<"type">>, type], <<>>)),
  Res =
    case T of
      <<"max_words">> ->
        Limit = openagentic_workflow_engine_utils:int_or_default(openagentic_workflow_engine_utils:get_any(G, [<<"value">>, value], undefined), 0),
        Count = openagentic_workflow_engine_output_helpers:word_count(Output),
        case (Limit > 0 andalso Count > Limit) of
          true -> {error, [iolist_to_binary([<<"max_words exceeded: ">>, integer_to_binary(Count), <<">">>, integer_to_binary(Limit)])]};
          false -> ok
        end;
      <<"regex_must_match">> ->
        Pat = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(G, [<<"pattern">>, pattern], <<>>)),
        case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
          match -> ok;
          _ -> {error, [<<"regex_must_match failed">>]}
        end;
      <<"markdown_sections">> ->
        Req = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(G, [<<"required">>, required], [])),
        case openagentic_workflow_engine_output_helpers:missing_sections(Req, Output) of
          [] -> ok;
          Missing -> {error, [iolist_to_binary([<<"missing sections: ">>, openagentic_workflow_engine_utils:join_bins([openagentic_workflow_engine_utils:to_bin(M) || M <- Missing], <<", ">>)])]}
        end;
      <<"decision_requires_reasons">> ->
        When = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(G, [<<"when">>, 'when'], <<>>)),
        Decision = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Parsed, [<<"decision">>, decision], <<>>)),
        case Decision =:= When of
          false -> ok;
          true ->
            ReasonsList = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(Parsed, [<<"reasons">>, reasons], [])),
            ChangesList = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(Parsed, [<<"required_changes">>, required_changes], [])),
            case (ReasonsList =/= []) andalso (ChangesList =/= []) of
              true -> ok;
              false -> {error, [<<"decision_requires_reasons failed">>]}
            end
        end;
      <<"requires_evidence">> ->
        %% v1 runner: advisory (enforced in async control plane later).
        ok;
      _ ->
        ok
    end,
  case Res of
    ok -> eval_guards(Rest, Output, Parsed);
    {error, Reasons} -> {error, Reasons}
  end.

step_next(StepRaw0, Parsed0) ->
  StepRaw = openagentic_workflow_engine_utils:ensure_map(StepRaw0),
  Parsed = openagentic_workflow_engine_utils:ensure_map(Parsed0),
  OnDecision0 = openagentic_workflow_engine_utils:get_any(StepRaw, [<<"on_decision">>, on_decision], undefined),
  OnDecision =
    case OnDecision0 of
      M when is_map(M) -> M;
      L when is_list(L) -> maps:from_list(L);
      _ -> #{}
    end,
  case maps:size(OnDecision) > 0 of
    false ->
      {openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_pass">>, on_pass]), <<>>};
    true ->
      Decision0 = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Parsed, [<<"decision">>, decision], <<>>)),
      Decision = string:trim(Decision0),
      case byte_size(Decision) > 0 of
        false ->
          {openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_pass">>, on_pass]), <<>>};
        true ->
          Key = string:lowercase(Decision),
          Next0 = maps:get(Key, OnDecision, maps:get(Decision, OnDecision, undefined)),
          Next =
            case Next0 of
              undefined -> openagentic_workflow_engine_utils:step_ref(StepRaw, [<<"on_pass">>, on_pass]);
              V -> V
            end,
          {Next, iolist_to_binary([<<"decision=">>, Decision])}
      end
  end.
