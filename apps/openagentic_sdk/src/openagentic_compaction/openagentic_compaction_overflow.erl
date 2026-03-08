-module(openagentic_compaction_overflow).
-export([would_overflow/2]).

would_overflow(Compaction0, Usage0) ->
  Compaction = openagentic_compaction_utils:ensure_map(Compaction0),
  Usage = openagentic_compaction_utils:ensure_map(Usage0),
  case parse_usage_totals(Usage) of
    undefined -> false;
    Totals ->
      ContextLimit = openagentic_compaction_utils:int_default(Compaction, [context_limit, contextLimit, <<"context_limit">>, <<"contextLimit">>], 0),
      case ContextLimit > 0 of
        false -> false;
        true ->
          OutputCap = openagentic_compaction_utils:int_default(Compaction, [global_output_cap, globalOutputCap, <<"global_output_cap">>, <<"globalOutputCap">>], 4096),
          OutputLimit0 = openagentic_compaction_utils:int_or_undef(Compaction, [output_limit, outputLimit, <<"output_limit">>, <<"outputLimit">>]),
          MaxOutputTokens = case OutputLimit0 of undefined -> OutputCap; V1 when V1 > 0 -> erlang:min(V1, OutputCap); _ -> OutputCap end,
          Reserved0 = openagentic_compaction_utils:int_or_undef(Compaction, [reserved]),
          Reserved = case Reserved0 of undefined -> erlang:min(20000, MaxOutputTokens); V2 when V2 > 0 -> V2; _ -> erlang:min(20000, MaxOutputTokens) end,
          InputLimit0 = openagentic_compaction_utils:int_or_undef(Compaction, [input_limit, inputLimit, <<"input_limit">>, <<"inputLimit">>]),
          Effective = case InputLimit0 of V3 when is_integer(V3), V3 > 0 -> V3; _ -> ContextLimit end,
          Usable = Effective - erlang:max(0, Reserved),
          TotalTokens = maps:get(total_tokens, Totals, 0),
          case Usable =< 0 of true -> true; false -> TotalTokens >= Usable end
      end
  end.

parse_usage_totals(Usage0) ->
  Usage = openagentic_compaction_utils:ensure_map(Usage0),
  case map_size(Usage) =:= 0 of
    true -> undefined;
    false ->
      InputTokens = pick_int(Usage, [<<"input_tokens">>, input_tokens, <<"prompt_tokens">>, prompt_tokens], 0),
      OutputTokens = pick_int(Usage, [<<"output_tokens">>, output_tokens, <<"completion_tokens">>, completion_tokens], 0),
      CacheRead = pick_int(Usage, [<<"cache_read_tokens">>, cache_read_tokens, <<"cached_tokens">>, cached_tokens], 0),
      CacheWrite = pick_int(Usage, [<<"cache_write_tokens">>, cache_write_tokens], 0),
      Total0 = pick_int(Usage, [<<"total_tokens">>, total_tokens], 0),
      Total = case Total0 > 0 of true -> Total0; false -> InputTokens + OutputTokens + CacheRead + CacheWrite end,
      case Total > 0 of false -> undefined; true -> #{input_tokens => erlang:max(0, InputTokens), output_tokens => erlang:max(0, OutputTokens), cache_read_tokens => erlang:max(0, CacheRead), cache_write_tokens => erlang:max(0, CacheWrite), total_tokens => erlang:max(0, Total)} end
  end.

pick_int(_Map, [], Default) -> Default;
pick_int(Map, [K | Rest], Default) ->
  case maps:get(K, Map, undefined) of undefined -> pick_int(Map, Rest, Default); V -> openagentic_compaction_utils:ensure_int(V, Default) end.
