-module(openagentic_case_scheduler_utils).
-export([clamp_range/3, compact_map/1, ensure_list/1, ensure_map/1, find_any/2, get_bin/3, get_in_map/3, int_or_default/2, to_bin/1]).

compact_map(Map0) -> maps:filter(fun (_K, V) -> V =/= undefined end, ensure_map(Map0)).

find_any(_Map, []) -> undefined;
find_any(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> find_any(Map, Rest);
    V -> V
  end.

get_in_map(Map0, [Key], Default) -> maps:get(Key, ensure_map(Map0), Default);
get_in_map(Map0, [Key | Rest], Default) ->
  case maps:get(Key, ensure_map(Map0), undefined) of
    undefined -> Default;
    Next -> get_in_map(Next, Rest, Default)
  end.

get_bin(Map0, [Key], Default) -> to_bin(maps:get(Key, ensure_map(Map0), Default));
get_bin(Map0, [Key | Rest], Default) ->
  case maps:get(Key, ensure_map(Map0), undefined) of
    undefined -> to_bin(Default);
    Next -> get_bin(Next, Rest, Default)
  end.

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
