-module(openagentic_runtime_truncate_headtail).
-export([head_tail_truncate/2,head_tail_truncate_loop/2,head_tail_truncate_loop2/4,head_tail_truncate_build/3,marker/1,bin_to_list_safe/1,int_default/3]).

head_tail_truncate(Text0, MaxChars0) ->
  Limit = erlang:max(0, MaxChars0),
  case Limit =< 0 of
    true -> <<>>;
    false ->
      TextList = bin_to_list_safe(Text0),
      case length(TextList) =< Limit of
        true -> unicode:characters_to_binary(TextList, utf8);
        false ->
          Truncated = head_tail_truncate_loop(TextList, Limit),
          unicode:characters_to_binary(Truncated, utf8)
      end
  end.

head_tail_truncate_loop(TextList, Limit) ->
  Len = length(TextList),
  Removed0 = erlang:max(0, Len - Limit),
  Marker0 = marker(Removed0),
  head_tail_truncate_loop2(TextList, Limit, Marker0, 0).

head_tail_truncate_loop2(TextList, Limit, Marker, Iter) when Iter >= 3 ->
  head_tail_truncate_build(TextList, Limit, Marker);

head_tail_truncate_loop2(TextList, Limit, Marker, Iter) ->
  Remaining = erlang:max(0, Limit - length(Marker)),
  case Remaining =< 0 of
    true ->
      lists:sublist(Marker, Limit);
    false ->
      HeadLen = Remaining div 2,
      TailLen = Remaining - HeadLen,
      Len = length(TextList),
      Removed = erlang:max(0, Len - HeadLen - TailLen),
      Marker2 = marker(Removed),
      case length(Marker2) =:= length(Marker) of
        true ->
          head_tail_truncate_build(TextList, Limit, Marker2);
        false ->
          head_tail_truncate_loop2(TextList, Limit, Marker2, Iter + 1)
      end
  end.

head_tail_truncate_build(TextList, Limit, Marker) ->
  Remaining = erlang:max(0, Limit - length(Marker)),
  case Remaining =< 0 of
    true ->
      lists:sublist(Marker, Limit);
    false ->
      HeadLen = Remaining div 2,
      TailLen = Remaining - HeadLen,
      Head = lists:sublist(TextList, HeadLen),
      Tail = lists:nthtail(length(TextList) - TailLen, TextList),
      Head ++ Marker ++ Tail
  end.

marker(Removed) ->
  lists:flatten(io_lib:format("\n…~p chars truncated…\n", [Removed])).

bin_to_list_safe(Bin) when is_binary(Bin) ->
  try
    unicode:characters_to_list(Bin, utf8)
  catch
    _:_ -> binary_to_list(Bin)
  end;
bin_to_list_safe(Other) ->
  openagentic_runtime_utils:ensure_list(Other).

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
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.
