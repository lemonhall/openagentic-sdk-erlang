-module(openagentic_compaction_transcript).
-export([build_compaction_transcript/4]).

build_compaction_transcript(Events0, ResumeMaxEvents, ResumeMaxBytes, ToolOutputPlaceholder) ->
  Trimmed = trim_events_for_resume(openagentic_compaction_utils:ensure_list(Events0), ResumeMaxEvents, ResumeMaxBytes),
  Compacted = openagentic_compaction_prune:compacted_ids_set(Trimmed),
  lists:filtermap(
    fun (E0) ->
      E = openagentic_compaction_utils:ensure_map(E0),
      case openagentic_compaction_utils:to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))) of
        <<"user.message">> -> {true, #{role => <<"user">>, content => openagentic_compaction_utils:to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>)))}};
        <<"user.compaction">> -> {true, #{role => <<"user">>, content => openagentic_compaction_prompts:compaction_marker_question()}};
        <<"assistant.message">> -> {true, #{role => <<"assistant">>, content => openagentic_compaction_utils:to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>)))}};
        <<"tool.use">> ->
          Name = openagentic_compaction_utils:to_bin(maps:get(name, E, maps:get(<<"name">>, E, <<>>))),
          Txt = iolist_to_binary([<<"[tool.call ">>, Name, <<"] ">>, openagentic_json:encode(openagentic_compaction_utils:ensure_map(maps:get(input, E, maps:get(<<"input">>, E, #{}))))]),
          {true, #{role => <<"assistant">>, content => Txt}};
        <<"tool.result">> ->
          Tid = openagentic_compaction_utils:to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          Content = case maps:get(Tid, Compacted, false) of true -> ToolOutputPlaceholder; false -> openagentic_json:encode(maps:get(output, E, maps:get(<<"output">>, E, null))) end,
          {true, #{role => <<"assistant">>, content => iolist_to_binary([<<"[tool.result ">>, Tid, <<"] ">>, Content])}};
        _ -> false
      end
    end,
    Trimmed
  ).

trim_events_for_resume(Events, MaxEvents0, MaxBytes0) ->
  MaxEvents = erlang:max(0, openagentic_compaction_utils:ensure_int(MaxEvents0, 0)),
  MaxBytes = erlang:max(0, openagentic_compaction_utils:ensure_int(MaxBytes0, 0)),
  case {MaxEvents =< 0, MaxBytes =< 0} of {true, true} -> Events; _ -> trim_events_for_resume_loop(lists:reverse(Events), MaxEvents, MaxBytes, [], 0) end.

trim_events_for_resume_loop([], _MaxEvents, _MaxBytes, Acc, _Bytes) -> lists:reverse(Acc);
trim_events_for_resume_loop([E | Rest], MaxEvents, MaxBytes, Acc0, Bytes0) ->
  case MaxEvents > 0 andalso length(Acc0) >= MaxEvents of
    true -> lists:reverse(Acc0);
    false ->
      Approx = safe_event_len(E),
      case MaxBytes > 0 andalso (Bytes0 + Approx) > MaxBytes andalso Acc0 =/= [] of
        true -> lists:reverse(Acc0);
        false -> trim_events_for_resume_loop(Rest, MaxEvents, MaxBytes, [E | Acc0], Bytes0 + Approx)
      end
  end.

safe_event_len(E0) ->
  try byte_size(openagentic_json:encode(openagentic_compaction_utils:ensure_map(E0))) catch _:_ -> 0 end.
