-module(openagentic_runtime_utils).
-export([ensure_map/1,ensure_list/1,to_bin/1]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list({ok, V}) -> ensure_list(V);
ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
