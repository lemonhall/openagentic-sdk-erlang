-module(openagentic_openai_responses_utils).

-export([ensure_map/1, ensure_list/1, get_req/2, to_list/1, to_bin/1]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

get_req(Key, Opts) ->
  case maps:get(Key, Opts, undefined) of
    undefined -> {error, {missing, Key}};
    V -> {ok, V}
  end.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

