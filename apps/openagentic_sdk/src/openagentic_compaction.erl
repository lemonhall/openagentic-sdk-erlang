-module(openagentic_compaction).

-export([
  would_overflow/2,
  select_tool_outputs_to_prune/2,
  build_compaction_transcript/4,
  tool_output_placeholder/0,
  compaction_system_prompt/0,
  compaction_user_instruction/0,
  compaction_marker_question/0
]).

%% Kotlin parity: Compaction constants.
compaction_system_prompt() ->
  <<
    "You are a helpful AI assistant tasked with summarizing conversations.\n\n"
    "When asked to summarize, provide a detailed but concise summary of the conversation.\n"
    "Focus on information that would be helpful for continuing the conversation, including:\n"
    "- What was done\n"
    "- What is currently being worked on\n"
    "- Which files are being modified\n"
    "- What needs to be done next\n"
    "- Key user requests, constraints, or preferences that should persist\n"
    "- Important technical decisions and why they were made\n\n"
    "Your summary should be comprehensive enough to provide context but concise enough to be quickly understood.\n"
  >>.

compaction_marker_question() ->
  <<"What did we do so far?">>.

compaction_user_instruction() ->
  <<
    "Provide a detailed prompt for continuing our conversation above. Focus on information that would be helpful for "
    "continuing the conversation, including what we did, what we're doing, which files we're working on, and what we're "
    "going to do next considering new session will not have access to our conversation."
  >>.

tool_output_placeholder() ->
  <<"[Old tool result content cleared]">>.

%% ---- overflow ----

would_overflow(Compaction0, Usage0) ->
  Compaction = ensure_map(Compaction0),
  Usage = ensure_map(Usage0),
  case parse_usage_totals(Usage) of
    undefined ->
      false;
    Totals ->
      ContextLimit = int_default(Compaction, [context_limit, contextLimit, <<"context_limit">>, <<"contextLimit">>], 0),
      case ContextLimit > 0 of
        false ->
          false;
        true ->
          OutputCap = int_default(Compaction, [global_output_cap, globalOutputCap, <<"global_output_cap">>, <<"globalOutputCap">>], 4096),
          OutputLimit0 = int_or_undef(Compaction, [output_limit, outputLimit, <<"output_limit">>, <<"outputLimit">>]),
          MaxOutputTokens =
            case OutputLimit0 of
              undefined -> OutputCap;
              V1 when V1 > 0 -> erlang:min(V1, OutputCap);
              _ -> OutputCap
            end,
          Reserved0 = int_or_undef(Compaction, [reserved]),
          Reserved =
            case Reserved0 of
              undefined -> erlang:min(20000, MaxOutputTokens);
              V2 when V2 > 0 -> V2;
              _ -> erlang:min(20000, MaxOutputTokens)
            end,
          InputLimit0 = int_or_undef(Compaction, [input_limit, inputLimit, <<"input_limit">>, <<"inputLimit">>]),
          Effective =
            case InputLimit0 of
              V3 when is_integer(V3), V3 > 0 -> V3;
              _ -> ContextLimit
            end,
          Usable = Effective - erlang:max(0, Reserved),
          TotalTokens = maps:get(total_tokens, Totals, 0),
          case Usable =< 0 of
            true -> true;
            false -> TotalTokens >= Usable
          end
      end
  end.

parse_usage_totals(Usage0) ->
  Usage = ensure_map(Usage0),
  case map_size(Usage) =:= 0 of
    true ->
      undefined;
    false ->
      InputTokens =
        pick_int(Usage, [<<"input_tokens">>, input_tokens, <<"prompt_tokens">>, prompt_tokens], 0),
      OutputTokens =
        pick_int(Usage, [<<"output_tokens">>, output_tokens, <<"completion_tokens">>, completion_tokens], 0),
      CacheRead =
        pick_int(Usage, [<<"cache_read_tokens">>, cache_read_tokens, <<"cached_tokens">>, cached_tokens], 0),
      CacheWrite =
        pick_int(Usage, [<<"cache_write_tokens">>, cache_write_tokens], 0),
      Total0 =
        pick_int(Usage, [<<"total_tokens">>, total_tokens], 0),
      Total =
        case Total0 > 0 of
          true -> Total0;
          false -> InputTokens + OutputTokens + CacheRead + CacheWrite
        end,
      case Total > 0 of
        false ->
          undefined;
        true ->
          #{
            input_tokens => erlang:max(0, InputTokens),
            output_tokens => erlang:max(0, OutputTokens),
            cache_read_tokens => erlang:max(0, CacheRead),
            cache_write_tokens => erlang:max(0, CacheWrite),
            total_tokens => erlang:max(0, Total)
          }
      end
  end.

pick_int(_Map, [], Default) -> Default;
pick_int(Map, [K | Rest], Default) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_int(Map, Rest, Default);
    V -> ensure_int(V, Default)
  end.

%% ---- prune tool outputs ----

select_tool_outputs_to_prune(Events0, Compaction0) ->
  Events = ensure_list(Events0),
  Compaction = ensure_map(Compaction0),
  Prune = bool_default(Compaction, [prune], true),
  case Prune of
    false ->
      [];
    true ->
      Protect = int_default(Compaction, [protect_tool_output_tokens, protectToolOutputTokens, <<"protect_tool_output_tokens">>, <<"protectToolOutputTokens">>], 40000),
      MinPrune = int_default(Compaction, [min_prune_tokens, minPruneTokens, <<"min_prune_tokens">>, <<"minPruneTokens">>], 20000),
      select_tool_outputs_to_prune_loop(Events, Protect, MinPrune)
  end.

select_tool_outputs_to_prune_loop(Events, Protect, MinPrune) ->
  Events2 = filter_to_latest_summary_pivot(Events),
  CompactedIds = compacted_ids_set(Events2),
  ToolNameById = tool_name_by_id(Events2),
  Rev = lists:reverse(Events2),
  scan_prune(Rev, CompactedIds, ToolNameById, Protect, MinPrune, 0, 0, [], 0).

filter_to_latest_summary_pivot(Events) ->
  %% Drop everything before the latest assistant.message(is_summary=true) pivot (inclusive behavior matches Kotlin: drop(idx)).
  Idx = last_summary_index(Events, 0, -1),
  case Idx < 0 of
    true -> Events;
    false -> lists:nthtail(Idx, Events)
  end.

last_summary_index([], _I, Last) -> Last;
last_summary_index([E0 | Rest], I, Last0) ->
  E = ensure_map(E0),
  Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
  IsSummary = bool_true(maps:get(is_summary, E, maps:get(<<"is_summary">>, E, false))),
  Last =
    case {Type, IsSummary} of
      {<<"assistant.message">>, true} -> I;
      _ -> Last0
    end,
  last_summary_index(Rest, I + 1, Last).

compacted_ids_set(Events) ->
  lists:foldl(
    fun (E0, Acc0) ->
      E = ensure_map(E0),
      Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
      case Type of
        <<"tool.output_compacted">> ->
          Tid = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          case byte_size(string:trim(Tid)) > 0 of true -> Acc0#{Tid => true}; false -> Acc0 end;
        _ -> Acc0
      end
    end,
    #{},
    Events
  ).

tool_name_by_id(Events) ->
  lists:foldl(
    fun (E0, Acc0) ->
      E = ensure_map(E0),
      Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
      case Type of
        <<"tool.use">> ->
          Tid = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          Name = to_bin(maps:get(name, E, maps:get(<<"name">>, E, <<>>))),
          case {byte_size(string:trim(Tid)) > 0, byte_size(string:trim(Name)) > 0} of
            {true, true} -> Acc0#{Tid => Name};
            _ -> Acc0
          end;
        _ -> Acc0
      end
    end,
    #{},
    Events
  ).

scan_prune([], _Compacted, _ToolNameById, _Protect, _MinPrune, _Total, Pruned, Acc, _Turns) ->
  case Pruned > _MinPrune of
    true -> [Tid || {Tid, _Cost} <- Acc];
    false -> []
  end;
scan_prune([E0 | Rest], Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0) ->
  E = ensure_map(E0),
  Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
  %% OpenCode parity: skip pruning until >=2 user turns are present.
  case Type of
    <<"user.message">> ->
      scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0 + 1);
    <<"user.compaction">> ->
      scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0 + 1);
    _ ->
      case Turns0 < 2 of
        true ->
          scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
        false ->
          case Type of
            <<"assistant.message">> ->
              IsSummary = bool_true(maps:get(is_summary, E, maps:get(<<"is_summary">>, E, false))),
              case IsSummary of
                true -> finalize_prune(Acc0, Pruned0, MinPrune);
                false -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0)
              end;
            <<"tool.result">> ->
              Tid = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
              case byte_size(string:trim(Tid)) > 0 of
                false ->
                  scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
                true ->
                  %% Idempotence boundary: once we hit an already-compacted tool result, stop scanning older results.
                  case maps:get(Tid, Compacted, false) of
                    true ->
                      finalize_prune(Acc0, Pruned0, MinPrune);
                    false ->
                      ToolName = to_bin(maps:get(Tid, ToolNameById, <<>>)),
                      case string:lowercase(string:trim(ToolName)) of
                        <<"skill">> ->
                          scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
                        _ ->
                          Out = maps:get(output, E, maps:get(<<"output">>, E, null)),
                          Cost = estimate_tokens(safe_json_dumps(Out)),
                          Total = Total0 + Cost,
                          case Total > Protect of
                            true ->
                              scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total, Pruned0 + Cost, Acc0 ++ [{Tid, Cost}], Turns0);
                            false ->
                              scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total, Pruned0, Acc0, Turns0)
                          end
                      end
                  end
              end;
            _ ->
              scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0)
          end
      end
  end.

finalize_prune(Acc0, Pruned0, MinPrune) ->
  case Pruned0 > MinPrune of
    true -> [Tid || {Tid, _} <- Acc0];
    false -> []
  end.

estimate_tokens(Text0) ->
  Text = ensure_list(Text0),
  Len = length(Text),
  case Len > 0 of
    false -> 0;
    true -> erlang:max(1, Len div 4)
  end.

safe_json_dumps(null) -> "null";
safe_json_dumps(undefined) -> "null";
safe_json_dumps(El) ->
  try
    binary_to_list(openagentic_json:encode(El))
  catch
    _:_ -> lists:flatten(io_lib:format("~p", [El]))
  end.

%% ---- transcript ----

build_compaction_transcript(Events0, ResumeMaxEvents, ResumeMaxBytes, ToolOutputPlaceholder) ->
  Events = ensure_list(Events0),
  Trimmed = trim_events_for_resume(Events, ResumeMaxEvents, ResumeMaxBytes),
  Compacted = compacted_ids_set(Trimmed),
  lists:filtermap(
    fun (E0) ->
      E = ensure_map(E0),
      Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
      case Type of
        <<"user.message">> ->
          Text = to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>))),
          {true, #{role => <<"user">>, content => Text}};
        <<"user.compaction">> ->
          {true, #{role => <<"user">>, content => compaction_marker_question()}};
        <<"assistant.message">> ->
          Text = to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>))),
          {true, #{role => <<"assistant">>, content => Text}};
        <<"tool.use">> ->
          Name = to_bin(maps:get(name, E, maps:get(<<"name">>, E, <<>>))),
          Args0 = ensure_map(maps:get(input, E, maps:get(<<"input">>, E, #{}))),
          ArgsJson = openagentic_json:encode(Args0),
          Txt = iolist_to_binary([<<"[tool.call ">>, Name, <<"] ">>, ArgsJson]),
          {true, #{role => <<"assistant">>, content => Txt}};
        <<"tool.result">> ->
          Tid = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          Content =
            case maps:get(Tid, Compacted, false) of
              true -> ToolOutputPlaceholder;
              false ->
                Out0 = maps:get(output, E, maps:get(<<"output">>, E, null)),
                openagentic_json:encode(Out0)
            end,
          Txt = iolist_to_binary([<<"[tool.result ">>, Tid, <<"] ">>, Content]),
          {true, #{role => <<"assistant">>, content => Txt}};
        _ ->
          false
      end
    end,
    Trimmed
  ).

trim_events_for_resume(Events, MaxEvents0, MaxBytes0) ->
  MaxEvents = erlang:max(0, ensure_int(MaxEvents0, 0)),
  MaxBytes = erlang:max(0, ensure_int(MaxBytes0, 0)),
  case {MaxEvents =< 0, MaxBytes =< 0} of
    {true, true} ->
      Events;
    _ ->
      trim_events_for_resume_loop(lists:reverse(Events), MaxEvents, MaxBytes, [], 0)
  end.

trim_events_for_resume_loop([], _MaxEvents, _MaxBytes, Acc, _Bytes) ->
  lists:reverse(Acc);
trim_events_for_resume_loop([E | Rest], MaxEvents, MaxBytes, Acc0, Bytes0) ->
  case (MaxEvents > 0 andalso length(Acc0) >= MaxEvents) of
    true ->
      lists:reverse(Acc0);
    false ->
      Approx = safe_event_len(E),
      case (MaxBytes > 0 andalso (Bytes0 + Approx) > MaxBytes andalso Acc0 =/= []) of
        true ->
          lists:reverse(Acc0);
        false ->
          trim_events_for_resume_loop(Rest, MaxEvents, MaxBytes, [E | Acc0], Bytes0 + Approx)
      end
  end.

safe_event_len(E0) ->
  try
    byte_size(openagentic_json:encode(ensure_map(E0)))
  catch
    _:_ -> 0
  end.

%% ---- utils ----

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

ensure_int(I, _Default) when is_integer(I) -> I;
ensure_int(B, Default) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of
    X when is_integer(X) -> X;
    _ -> Default
  end;
ensure_int(L, Default) when is_list(L) ->
  ensure_int(unicode:characters_to_binary(L, utf8), Default);
ensure_int(_, Default) ->
  Default.

int_default(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  ensure_int(Val, Default).

int_or_undef(Map, Keys) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> undefined;
    _ -> ensure_int(Val, undefined)
  end.

bool_default(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    _ -> bool_true(Val)
  end.

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of
    <<"true">> -> true;
    <<"1">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    _ -> false
  end;
bool_true(L) when is_list(L) ->
  bool_true(unicode:characters_to_binary(L, utf8));
bool_true(I) when is_integer(I) ->
  I =/= 0;
bool_true(_) ->
  false.
