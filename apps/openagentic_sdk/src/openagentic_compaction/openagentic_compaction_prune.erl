-module(openagentic_compaction_prune).
-export([compacted_ids_set/1, estimate_tokens/1, select_tool_outputs_to_prune/2]).

select_tool_outputs_to_prune(Events0, Compaction0) ->
  Events = openagentic_compaction_utils:ensure_list(Events0),
  Compaction = openagentic_compaction_utils:ensure_map(Compaction0),
  case openagentic_compaction_utils:bool_default(Compaction, [prune], true) of
    false -> [];
    true ->
      Protect = openagentic_compaction_utils:int_default(Compaction, [protect_tool_output_tokens, protectToolOutputTokens, <<"protect_tool_output_tokens">>, <<"protectToolOutputTokens">>], 40000),
      MinPrune = openagentic_compaction_utils:int_default(Compaction, [min_prune_tokens, minPruneTokens, <<"min_prune_tokens">>, <<"minPruneTokens">>], 20000),
      select_tool_outputs_to_prune_loop(Events, Protect, MinPrune)
  end.

select_tool_outputs_to_prune_loop(Events, Protect, MinPrune) ->
  Events2 = filter_to_latest_summary_pivot(Events),
  Rev = lists:reverse(Events2),
  scan_prune(Rev, compacted_ids_set(Events2), tool_name_by_id(Events2), Protect, MinPrune, 0, 0, [], 0).

filter_to_latest_summary_pivot(Events) ->
  case last_summary_index(Events, 0, -1) of Idx when Idx < 0 -> Events; Idx -> lists:nthtail(Idx, Events) end.

last_summary_index([], _I, Last) -> Last;
last_summary_index([E0 | Rest], I, Last0) ->
  E = openagentic_compaction_utils:ensure_map(E0),
  Type = openagentic_compaction_utils:to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
  IsSummary = openagentic_compaction_utils:bool_true(maps:get(is_summary, E, maps:get(<<"is_summary">>, E, false))),
  Last = case {Type, IsSummary} of {<<"assistant.message">>, true} -> I; _ -> Last0 end,
  last_summary_index(Rest, I + 1, Last).

compacted_ids_set(Events) ->
  lists:foldl(
    fun (E0, Acc0) ->
      E = openagentic_compaction_utils:ensure_map(E0),
      case openagentic_compaction_utils:to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))) of
        <<"tool.output_compacted">> ->
          Tid = openagentic_compaction_utils:to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
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
      E = openagentic_compaction_utils:ensure_map(E0),
      case openagentic_compaction_utils:to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))) of
        <<"tool.use">> ->
          Tid = openagentic_compaction_utils:to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          Name = openagentic_compaction_utils:to_bin(maps:get(name, E, maps:get(<<"name">>, E, <<>>))),
          case {byte_size(string:trim(Tid)) > 0, byte_size(string:trim(Name)) > 0} of {true, true} -> Acc0#{Tid => Name}; _ -> Acc0 end;
        _ -> Acc0
      end
    end,
    #{},
    Events
  ).

scan_prune([], _Compacted, _ToolNameById, _Protect, MinPrune, _Total, Pruned, Acc, _Turns) ->
  case Pruned > MinPrune of true -> [Tid || {Tid, _Cost} <- Acc]; false -> [] end;
scan_prune([E0 | Rest], Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0) ->
  E = openagentic_compaction_utils:ensure_map(E0),
  Type = openagentic_compaction_utils:to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
  case Type of
    <<"user.message">> -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0 + 1);
    <<"user.compaction">> -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0 + 1);
    _ when Turns0 < 2 -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
    <<"assistant.message">> ->
      case openagentic_compaction_utils:bool_true(maps:get(is_summary, E, maps:get(<<"is_summary">>, E, false))) of true -> finalize_prune(Acc0, Pruned0, MinPrune); false -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0) end;
    <<"tool.result">> ->
      Tid = openagentic_compaction_utils:to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
      case byte_size(string:trim(Tid)) > 0 of
        false -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
        true ->
          case maps:get(Tid, Compacted, false) of
            true -> finalize_prune(Acc0, Pruned0, MinPrune);
            false ->
              ToolName = openagentic_compaction_utils:to_bin(maps:get(Tid, ToolNameById, <<>>)),
              case string:lowercase(string:trim(ToolName)) of
                <<"skill">> -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0);
                _ ->
                  Cost = estimate_tokens(openagentic_compaction_utils:safe_json_dumps(maps:get(output, E, maps:get(<<"output">>, E, null)))),
                  Total = Total0 + Cost,
                  case Total > Protect of
                    true -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total, Pruned0 + Cost, Acc0 ++ [{Tid, Cost}], Turns0);
                    false -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total, Pruned0, Acc0, Turns0)
                  end
              end
          end
      end;
    _ -> scan_prune(Rest, Compacted, ToolNameById, Protect, MinPrune, Total0, Pruned0, Acc0, Turns0)
  end.

finalize_prune(Acc0, Pruned0, MinPrune) -> case Pruned0 > MinPrune of true -> [Tid || {Tid, _} <- Acc0]; false -> [] end.

estimate_tokens(Text0) ->
  case length(openagentic_compaction_utils:ensure_list(Text0)) of 0 -> 0; Len -> erlang:max(1, Len div 4) end.
