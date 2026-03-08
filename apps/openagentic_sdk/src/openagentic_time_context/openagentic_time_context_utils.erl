-module(openagentic_time_context_utils).

-export([ensure_map/1, first_non_blank/1, get_any/3, pick_opt/2, to_bin/1, to_list/1]).

pick_opt(_Map, []) -> undefined;
pick_opt(Map, [Key | Rest]) -> case maps:get(Key, Map, undefined) of undefined -> pick_opt(Map, Rest); Value -> Value end.

get_any(_Map, [], Default) -> Default;
get_any(Map, [Key | Rest], Default) -> case maps:get(Key, Map, undefined) of undefined -> get_any(Map, Rest, Default); Value -> Value end.

first_non_blank([]) -> <<>>;
first_non_blank([Value | Rest]) ->
  Bin = string:trim(to_bin(Value)),
  case Bin of <<>> -> first_non_blank(Rest); <<"undefined">> -> first_non_blank(Rest); _ -> Bin end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(undefined) -> "";
to_list(B) when is_binary(B) -> unicode:characters_to_list(B, utf8);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(I) when is_integer(I) -> integer_to_list(I);
to_list(Other) -> io_lib:format("~p", [Other]).
