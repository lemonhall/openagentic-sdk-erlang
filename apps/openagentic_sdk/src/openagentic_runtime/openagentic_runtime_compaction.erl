-module(openagentic_runtime_compaction).
-export([maybe_prune_tool_outputs/1,maybe_run_compaction_overflow/2,run_compaction_pass/1]).

maybe_prune_tool_outputs(State0) ->
  Compaction = openagentic_runtime_utils:ensure_map(maps:get(compaction, State0, #{})),
  Prune = maps:get(prune, Compaction, maps:get(<<"prune">>, Compaction, true)),
  case Prune of
    false ->
      State0;
    _ ->
      Ids = openagentic_compaction:select_tool_outputs_to_prune(maps:get(events, State0, []), Compaction),
      case Ids of
        [] -> State0;
        _ ->
          Now = erlang:system_time(millisecond) / 1000.0,
          lists:foldl(
            fun (Tid0, Acc) ->
              Tid = openagentic_runtime_utils:to_bin(Tid0),
              openagentic_runtime_events:append_event(Acc, openagentic_events:tool_output_compacted(Tid, Now))
            end,
            State0,
            Ids
          )
      end
  end.

maybe_run_compaction_overflow(ModelOut, State0) ->
  Compaction = openagentic_runtime_utils:ensure_map(maps:get(compaction, State0, #{})),
  Auto = maps:get(auto, Compaction, maps:get(<<"auto">>, Compaction, true)),
  SupportsPrev = maps:get(supports_previous_response_id, State0, true),
  Protocol = maps:get(protocol, State0, responses),
  %% Kotlin parity: overflow compaction is eligible for legacy, or for responses providers that can't rely on previous_response_id.
  Eligible = (Auto =:= true) andalso ((Protocol =:= legacy) orelse (SupportsPrev =:= false)),
  Usage = maps:get(usage, openagentic_runtime_utils:ensure_map(ModelOut), undefined),
  case Eligible andalso openagentic_compaction:would_overflow(Compaction, openagentic_runtime_utils:ensure_map(Usage)) of
    true ->
      State1 = openagentic_runtime_events:append_event(State0, openagentic_events:user_compaction(true, <<"overflow">>)),
      State2 = run_compaction_pass(State1),
      {compacted, State2#{previous_response_id := undefined}};
    false ->
      {no_compaction, State0}
  end.

run_compaction_pass(State0) ->
  Root = maps:get(root, State0),
  Sid0 = maps:get(session_id, State0, <<>>),
  Sid = openagentic_runtime_utils:to_bin(Sid0),
  ResumeMaxEvents = maps:get(resume_max_events, State0, 1000),
  ResumeMaxBytes = maps:get(resume_max_bytes, State0, 2000000),
  Events0 = openagentic_session_store:read_events(Root, Sid),
  History =
    openagentic_compaction:build_compaction_transcript(
      Events0,
      ResumeMaxEvents,
      ResumeMaxBytes,
      openagentic_compaction:tool_output_placeholder()
    ),
  InputItems =
    [#{role => <<"system">>, content => openagentic_compaction:compaction_system_prompt()}] ++
      History ++
      [#{role => <<"user">>, content => openagentic_compaction:compaction_user_instruction()}],
  ProviderMod = maps:get(provider_mod, State0),
  RetryCfg = maps:get(provider_retry, State0, #{}),
  Req0 = openagentic_runtime_options:build_provider_opts(State0, InputItems, []),
  Req = Req0#{store => false},
  case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Req) end, RetryCfg) of
    {ok, ModelOut} ->
      Summary = maps:get(assistant_text, openagentic_runtime_utils:ensure_map(ModelOut), <<>>),
      case byte_size(string:trim(openagentic_runtime_utils:to_bin(Summary))) > 0 of
        true -> openagentic_runtime_events:append_event(State0, openagentic_events:assistant_message(Summary, true));
        false -> State0
      end;
    {error, Reason} ->
      %% Best-effort: record error and continue without compaction.
      openagentic_runtime_events:append_event(State0, openagentic_events:runtime_error(<<"compaction">>, <<"CompactionError">>, openagentic_runtime_utils:to_bin(Reason), openagentic_runtime_utils:to_bin(ProviderMod), undefined))
  end.
