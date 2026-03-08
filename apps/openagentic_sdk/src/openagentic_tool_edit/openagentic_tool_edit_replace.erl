-module(openagentic_tool_edit_replace).

-export([occurrences/2, replace_n/4]).

occurrences(Text, Old) ->
  case Old of
    <<>> -> 0;
    _ ->
      Parts = binary:split(Text, Old, [global]),
      case length(Parts) of
        0 -> 0;
        N -> N - 1
      end
  end.

replace_n(Text, _Old, _New, Count) when Count =< 0 ->
  Text;
replace_n(Text, Old, New, Count) ->
  case binary:match(Text, Old) of
    nomatch ->
      Text;
    {Idx, Len} ->
      Prefix = binary:part(Text, 0, Idx),
      Suffix = binary:part(Text, Idx + Len, byte_size(Text) - (Idx + Len)),
      replace_n(iolist_to_binary([Prefix, New, Suffix]), Old, New, Count - 1)
  end.
