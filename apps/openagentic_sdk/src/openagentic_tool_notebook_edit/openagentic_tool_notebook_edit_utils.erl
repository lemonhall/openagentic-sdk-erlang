-module(openagentic_tool_notebook_edit_utils).

-export([trim_non_empty/1, random_hex/1, ensure_map/1, ensure_list/1, to_bin/1]).

trim_non_empty(undefined) -> undefined;
trim_non_empty(V0) ->
  V = to_bin(V0),
  case byte_size(string:trim(V)) > 0 of
    true -> V;
    false -> undefined
  end.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
