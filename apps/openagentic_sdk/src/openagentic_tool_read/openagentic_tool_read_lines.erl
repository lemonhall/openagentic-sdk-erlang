-module(openagentic_tool_read_lines).

-export([decode_text_utf8/1, ends_with/2, join_numbered/2, normalize_offset_opt/1, slice_list/3, split_lines_clamped/2]).

normalize_offset_opt(undefined) -> undefined;
normalize_offset_opt(Int) when is_integer(Int), Int =:= 0 -> 1;
normalize_offset_opt(Int) when is_integer(Int) -> Int;
normalize_offset_opt(_) -> undefined.

join_numbered(Lines, Start0) ->
  Start = erlang:max(0, Start0),
  case Lines of
    [] -> <<>>;
    _ ->
      Indexes = lists:seq(0, length(Lines) - 1),
      iolist_to_binary(lists:join(<<"
">>, [iolist_to_binary([integer_to_list(Start + Index + 1), <<": ">>, Line]) || {Index, Line} <- lists:zip(Indexes, Lines)]))
  end.

split_lines_clamped(TextBin, MaxLineChars) when is_binary(TextBin) ->
  Raw = binary:split(TextBin, <<"
">>, [global]),
  Lines1 = [strip_cr(Line) || Line <- Raw],
  Lines2 =
    case ends_with(TextBin, <<"
">>) of
      true ->
        case Lines1 of
          [] -> [];
          _ ->
            case lists:last(Lines1) of
              <<>> -> lists:sublist(Lines1, length(Lines1) - 1);
              _ -> Lines1
            end
        end;
      false ->
        Lines1
    end,
  clamp_lines(Lines2, MaxLineChars).

clamp_lines(Lines, Max) ->
  lists:foldr(
    fun (Line, {Acc, Trunc}) ->
      case string:length(Line) =< Max of
        true -> {[Line | Acc], Trunc};
        false ->
          Prefix = string:slice(Line, 0, Max),
          {[<<Prefix/binary, "…(truncated)">> | Acc], true}
      end
    end,
    {[], false},
    Lines
  ).

strip_cr(Line) ->
  case byte_size(Line) of
    0 -> <<>>;
    Size ->
      RestSize = Size - 1,
      case Line of
        <<Rest:RestSize/binary, $>> -> Rest;
        _ -> Line
      end
  end.

decode_text_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> unicode:characters_to_binary(Bin, latin1)
  end.

ends_with(Bin, Suffix) ->
  BinSize = byte_size(Bin),
  SuffixSize = byte_size(Suffix),
  BinSize >= SuffixSize andalso binary:part(Bin, BinSize - SuffixSize, SuffixSize) =:= Suffix.

slice_list(List, Start0, End0) ->
  Start = erlang:max(0, Start0),
  End = erlang:max(Start, End0),
  take(drop(List, Start), End - Start).

drop(List, 0) -> List;
drop([], _Count) -> [];
drop([_ | Tail], Count) when Count > 0 -> drop(Tail, Count - 1).

take(_List, 0) -> [];
take([], _Count) -> [];
take([Head | Tail], Count) when Count > 0 -> [Head | take(Tail, Count - 1)].
