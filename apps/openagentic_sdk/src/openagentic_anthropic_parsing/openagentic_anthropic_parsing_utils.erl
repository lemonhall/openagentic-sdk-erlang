-module(openagentic_anthropic_parsing_utils).

-export([pick_first/2, ensure_map/1, ensure_list/1, to_bin/1, bin_trim/1]).

pick_first(_Map, []) ->
  undefined;
pick_first(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_first(Map, Rest);
    V -> V
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bin_trim(B) ->
  string:trim(to_bin(B)).
