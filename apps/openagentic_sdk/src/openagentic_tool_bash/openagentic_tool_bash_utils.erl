-module(openagentic_tool_bash_utils).

-export([ensure_list/1, ensure_map/1, first_int/2, first_number/2, random_hex/1, to_bin/1, trim_non_empty/1]).

trim_non_empty(undefined) -> undefined;
trim_non_empty(Value0) ->
  Value = to_bin(Value0),
  case byte_size(string:trim(Value)) > 0 of
    true -> Value;
    false -> undefined
  end.

first_int(Map, Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Acc of
        undefined -> to_int(maps:get(Key, Map, undefined));
        _ -> Acc
      end
    end,
    undefined,
    Keys
  ).

to_int(undefined) -> undefined;
to_int(Int) when is_integer(Int) -> Int;
to_int(Bin) when is_binary(Bin) ->
  case catch binary_to_integer(string:trim(Bin)) of
    Int when is_integer(Int) -> Int;
    _ -> undefined
  end;
to_int(List) when is_list(List) ->
  case catch list_to_integer(string:trim(List)) of
    Int when is_integer(Int) -> Int;
    _ -> undefined
  end;
to_int(_) -> undefined.

first_number(Map, Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Acc of
        undefined -> to_number(maps:get(Key, Map, undefined));
        _ -> Acc
      end
    end,
    undefined,
    Keys
  ).

to_number(undefined) -> undefined;
to_number(Int) when is_integer(Int) -> Int * 1.0;
to_number(Float) when is_float(Float) -> Float;
to_number(Bin) when is_binary(Bin) ->
  case catch list_to_float(binary_to_list(string:trim(Bin))) of
    Float when is_float(Float) -> Float;
    _ ->
      case catch binary_to_integer(string:trim(Bin)) of
        Int when is_integer(Int) -> Int * 1.0;
        _ -> undefined
      end
  end;
to_number(List) when is_list(List) ->
  case catch list_to_float(string:trim(List)) of
    Float when is_float(Float) -> Float;
    _ ->
      case catch list_to_integer(string:trim(List)) of
        Int when is_integer(Int) -> Int * 1.0;
        _ -> undefined
      end
  end;
to_number(_) -> undefined.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  lists:flatten([io_lib:format("~2.16.0b", [Byte]) || <<Byte:8>> <= Bytes]).

ensure_map(Map) when is_map(Map) -> Map;
ensure_map(List) when is_list(List) -> maps:from_list(List);
ensure_map(_) -> #{}.

ensure_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
ensure_list(List) when is_list(List) -> List;
ensure_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> unicode:characters_to_binary(List, utf8);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Int) when is_integer(Int) -> iolist_to_binary(integer_to_list(Int));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
