-module(openagentic_tool_websearch_utils).

-export([ensure_map/1, int_opt/3, string_list/3, to_bin/1, to_bin_safe_utf8/1, to_list/1, trim_bin/1]).

string_list(Input, KeyBin, KeyAtom) ->
  case maps:get(KeyBin, Input, maps:get(KeyAtom, Input, [])) of
    List when is_list(List) ->
      [string:lowercase(string:trim(to_bin(Item))) || Item <- List, byte_size(string:trim(to_bin(Item))) > 0];
    _ -> []
  end.

int_opt(Map, Keys, Default) ->
  Value =
    lists:foldl(
      fun (Key, Acc) ->
        case Acc of
          undefined -> maps:get(Key, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Value of
    undefined -> Default;
    Int when is_integer(Int) -> Int;
    Bin when is_binary(Bin) -> parse_int_or_default(binary_to_integer_safe(string:trim(Bin)), Default);
    List when is_list(List) -> parse_int_or_default(list_to_integer_safe(string:trim(List)), Default);
    _ -> Default
  end.

parse_int_or_default(Int, _Default) when is_integer(Int) -> Int;
parse_int_or_default(_, Default) -> Default.

binary_to_integer_safe(Bin) ->
  case catch binary_to_integer(Bin) of
    Int when is_integer(Int) -> Int;
    _ -> error
  end.

list_to_integer_safe(List) ->
  case catch list_to_integer(List) of
    Int when is_integer(Int) -> Int;
    _ -> error
  end.

ensure_map(Map) when is_map(Map) -> Map;
ensure_map(List) when is_list(List) -> maps:from_list(List);
ensure_map(_) -> #{}.

to_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
to_list(List) when is_list(List) -> List;
to_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> unicode:characters_to_binary(List, utf8);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Int) when is_integer(Int) -> iolist_to_binary(integer_to_list(Int));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_bin_safe_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end;
to_bin_safe_utf8(Other) ->
  to_bin(Other).

trim_bin(Bin0) ->
  Bin = to_bin(Bin0),
  string:trim(Bin).
