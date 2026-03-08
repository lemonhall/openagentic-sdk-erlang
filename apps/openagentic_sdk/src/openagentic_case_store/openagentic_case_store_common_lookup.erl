-module(openagentic_case_store_common_lookup).
-export([choose_map/3, get_in_map/3, required_bin/2, get_bin/3, get_int/3, get_number/3, get_list/3, get_bool/3, find_any/2, find_any_keys/2, expand_keys/1]).

choose_map(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> openagentic_case_store_common_core:ensure_map(Default);
    Value -> openagentic_case_store_common_core:ensure_map(Value)
  end.

get_in_map(Map0, [Key], Default) ->
  case find_any(openagentic_case_store_common_core:ensure_map(Map0), [Key]) of
    undefined -> Default;
    Value -> Value
  end;
get_in_map(Map0, [Key | Rest], Default) ->
  Map = openagentic_case_store_common_core:ensure_map(Map0),
  case find_any(Map, [Key]) of
    undefined -> Default;
    Value -> get_in_map(Value, Rest, Default)
  end.

required_bin(Map, Keys) ->
  case get_bin(Map, Keys, undefined) of
    undefined -> erlang:error({missing_required_field, hd(Keys)});
    <<>> -> erlang:error({missing_required_field, hd(Keys)});
    Value -> Value
  end.

get_bin(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    null -> Default;
    Value ->
      Bin = openagentic_case_store_common_core:to_bin(Value),
      case openagentic_case_store_common_core:trim_bin(Bin) of
        <<>> -> Default;
        Trimmed -> Trimmed
      end
  end.

get_int(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    Value when is_integer(Value) -> Value;
    Value when is_binary(Value) ->
      case catch binary_to_integer(openagentic_case_store_common_core:trim_bin(Value)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    Value when is_list(Value) ->
      case catch list_to_integer(string:trim(Value)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

get_number(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    V when is_integer(V) -> V;
    V when is_float(V) -> V;
    _ -> Default
  end.

get_list(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    null -> Default;
    Value when is_list(Value) -> Value;
    Value -> [Value]
  end.

get_bool(Map, Keys, Default) ->
  case find_any(Map, Keys) of
    undefined -> Default;
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    "true" -> true;
    "false" -> false;
    _ -> Default
  end.

find_any(Map0, Keys0) ->
  Map = openagentic_case_store_common_core:ensure_map(Map0),
  Keys = expand_keys(Keys0),
  find_any_keys(Map, Keys).

find_any_keys(_Map, []) -> undefined;
find_any_keys(Map, [Key | Rest]) ->
  case maps:find(Key, Map) of
    {ok, Value} -> Value;
    error -> find_any_keys(Map, Rest)
  end.

expand_keys(Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Key of
        K when is_atom(K) -> [K, atom_to_binary(K, utf8) | Acc];
        K when is_binary(K) ->
          Atom = catch binary_to_existing_atom(K, utf8),
          case is_atom(Atom) of
            true -> [K, Atom | Acc];
            false -> [K | Acc]
          end;
        Other -> [Other | Acc]
      end
    end,
    [],
    Keys
  ).
