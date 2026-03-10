-module(openagentic_case_scheduler_utils).
-export([clamp_range/3, compact_map/1, ensure_list/1, ensure_map/1, find_any/2, get_bin/3, get_in_map/3, int_or_default/2, to_bin/1]).

compact_map(Map0) -> maps:filter(fun (_K, V) -> V =/= undefined end, ensure_map(Map0)).

find_any(Map0, Keys0) ->
  Map = ensure_map(Map0),
  Keys = expand_keys(Keys0),
  find_any_keys(Map, Keys).

find_any_keys(_Map, []) -> undefined;
find_any_keys(Map, [Key | Rest]) ->
  case maps:find(Key, Map) of
    {ok, Value} -> Value;
    error -> find_any_keys(Map, Rest)
  end.

get_in_map(Map0, [Key], Default) ->
  case find_any(ensure_map(Map0), [Key]) of
    undefined -> Default;
    Value -> Value
  end;
get_in_map(Map0, [Key | Rest], Default) ->
  case find_any(ensure_map(Map0), [Key]) of
    undefined -> Default;
    Next -> get_in_map(Next, Rest, Default)
  end.

get_bin(Map0, Keys, Default) ->
  case find_any(Map0, Keys) of
    undefined -> to_bin(Default);
    Value -> to_bin(Value)
  end.

expand_keys(Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Key of
        K when is_atom(K) -> [K, atom_to_binary(K, utf8) | Acc];
        K when is_binary(K) ->
          case catch binary_to_existing_atom(K, utf8) of
            Atom when is_atom(Atom) -> [K, Atom | Acc];
            _ -> [K | Acc]
          end;
        Other -> [Other | Acc]
      end
    end,
    [],
    Keys
  ).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(F) when is_float(F) -> list_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) -> case catch binary_to_integer(string:trim(B)) of I when is_integer(I) -> I; _ -> Default end;
    L when is_list(L) -> case catch list_to_integer(string:trim(L)) of I when is_integer(I) -> I; _ -> Default end;
    _ -> Default
  end.

clamp_range(Value, Min, Max) -> erlang:min(Max, erlang:max(Min, Value)).
