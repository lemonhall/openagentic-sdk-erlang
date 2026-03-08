-module(openagentic_openai_chat_completions_utils).

-export([bin_to_list_safe/1, ensure_list/1, ensure_map/1, get_req/2, to_bin/1, to_list/1]).

get_req(Key, Map) ->
  case maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)) of
    undefined -> {error, {missing, Key}};
    <<>> -> {error, {missing, Key}};
    "" -> {error, {missing, Key}};
    V -> {ok, V}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [B];
ensure_list(_) -> [].

bin_to_list_safe(Bin) when is_binary(Bin) ->
  try unicode:characters_to_list(Bin, utf8) catch _:_ -> binary_to_list(Bin) end;
bin_to_list_safe(Other) ->
  ensure_list(Other).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(F) when is_float(F) -> unicode:characters_to_binary(io_lib:format("~p", [F]), utf8);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(undefined) -> "";
to_list(null) -> "";
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(I) when is_integer(I) -> integer_to_list(I);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
