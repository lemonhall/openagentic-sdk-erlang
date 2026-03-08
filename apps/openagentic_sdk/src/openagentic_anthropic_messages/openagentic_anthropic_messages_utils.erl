-module(openagentic_anthropic_messages_utils).

-export([get_req/2, ensure_map/1, ensure_list/1, to_list/1, to_bin/1]).

get_req(Key, Map) ->
  case maps:get(Key, Map, maps:get(list_to_binary(atom_to_list(Key)), Map, undefined)) of
    undefined -> {error, {missing, Key}};
    null -> {error, {missing, Key}};
    <<>> -> {error, {missing, Key}};
    "" -> {error, {missing, Key}};
    V -> {ok, V}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
