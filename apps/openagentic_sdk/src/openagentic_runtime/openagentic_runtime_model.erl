-module(openagentic_runtime_model).
-export([call_model/1,handle_model_output/2]).

call_model(State0) ->
  Events = maps:get(events, State0, []),
  InputItems0 = openagentic_model_input:build_responses_input(Events),
  InputItems = openagentic_runtime_permissions:maybe_prepend_system_prompt(State0, InputItems0),
  ProviderMod = maps:get(provider_mod, State0),
  ToolSchemas = maps:get(tool_schemas, State0, []),
  Opts = openagentic_runtime_options:build_provider_opts(State0, InputItems, ToolSchemas),
  RetryCfg = maps:get(provider_retry, State0, #{}),
  OptsD =
    case maps:get(include_partial_messages, State0, false) of
      true ->
        Sink = fun (DeltaBin) -> openagentic_runtime_events:emit_transient_event(State0, openagentic_events:assistant_delta(DeltaBin)) end,
        Opts#{on_delta => Sink};
      false ->
        Opts
    end,
  PrevId = maps:get(previous_response_id, State0, undefined),
  SupportsPrev = maps:get(supports_previous_response_id, State0, true),
  Protocol = maps:get(protocol, State0, responses),
  Opts2 =
    case {Protocol, SupportsPrev, PrevId} of
      {responses, true, undefined} -> OptsD;
      {responses, true, <<>>} -> OptsD;
      {responses, true, ""} -> OptsD;
      {responses, true, PrevVal} -> OptsD#{previous_response_id => PrevVal};
      _ -> OptsD
    end,
  case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Opts2) end, RetryCfg) of
    {ok, ModelOut} ->
      RespId = maps:get(response_id, ModelOut, undefined),
      State1 =
        case RespId of
          undefined -> State0;
          _ -> State0#{previous_response_id := RespId}
        end,
      {ok, ModelOut, openagentic_runtime_finalize:bump_steps(State1)};
    {error, Reason} ->
      %% Kotlin-aligned fallback: if prev id breaks, retry without it once.
      Msg = string:lowercase(iolist_to_binary(io_lib:format("~p", [Reason]))),
      LooksPrev = (binary:match(Msg, <<"previous_response_id">>) =/= nomatch) orelse (binary:match(Msg, <<"previous response">>) =/= nomatch),
      case {Protocol, SupportsPrev, PrevId, LooksPrev} of
        {responses, true, PrevVal2, true} when PrevVal2 =/= undefined, PrevVal2 =/= <<>>, PrevVal2 =/= "" ->
          State1 = State0#{supports_previous_response_id := false},
          Opts3 = maps:remove(previous_response_id, OptsD),
          case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Opts3) end, RetryCfg) of
            {ok, ModelOut2} ->
              RespId2 = maps:get(response_id, ModelOut2, undefined),
              State2 =
                case RespId2 of
                  undefined -> State1;
                  _ -> State1#{previous_response_id := RespId2}
                end,
              {ok, ModelOut2, openagentic_runtime_finalize:bump_steps(State2)};
            {error, Reason2} ->
              {error, Reason2, openagentic_runtime_finalize:bump_steps(State1)}
          end;
        _ ->
          {error, Reason, openagentic_runtime_finalize:bump_steps(State0)}
      end
  end.

handle_model_output(ModelOut0, State0) ->
  ModelOut = openagentic_runtime_utils:ensure_map(ModelOut0),
  ToolCalls = maps:get(tool_calls, ModelOut, []),
  case ToolCalls of
    [] ->
      AssistantText = maps:get(assistant_text, ModelOut, <<>>),
      State1 =
        case AssistantText of
          <<>> -> State0;
          _ -> openagentic_runtime_events:append_event(State0, openagentic_events:assistant_message(AssistantText))
        end,
      %% Kotlin parity: after tool loop, optionally run compaction on overflow (eligible when we can't rely on previous_response_id).
      case openagentic_runtime_compaction:maybe_run_compaction_overflow(ModelOut, State1) of
        {compacted, StateC} ->
          openagentic_runtime_loop:run_loop(StateC);
         {no_compaction, StateNC} ->
      Usage0 = maps:get(usage, ModelOut, undefined),
      Usage =
        case Usage0 of
          null -> undefined;
          U when is_map(U) -> U;
          _ -> undefined
        end,
      ResponseId0 = maps:get(previous_response_id, StateNC, undefined),
      ResponseId1 = string:trim(openagentic_runtime_utils:to_bin(ResponseId0)),
      ResponseId =
        case ResponseId1 of
          <<>> -> undefined;
          <<"undefined">> -> undefined;
          _ -> ResponseId1
        end,
      Steps = maps:get(steps, State1, 0),
      Sid = maps:get(session_id, State1, <<>>),
      State2 =
        openagentic_runtime_events:append_event(
          StateNC,
          openagentic_events:result(
            AssistantText,
            Sid,
            <<"end">>,
            Usage,
            ResponseId,
            undefined,
            Steps
          )
        ),
      {ok, #{session_id => maps:get(session_id, State2), final_text => AssistantText}}
      end;
    _ ->
      State1 = lists:foldl(fun openagentic_runtime_tools:run_one_tool_call/2, State0, ToolCalls),
      State2 = openagentic_runtime_compaction:maybe_prune_tool_outputs(State1),
      openagentic_runtime_loop:run_loop(State2)
  end.
