-module(openagentic_session_store_utils).

-export([ensure_list/1, ensure_map/1, to_bin/1, with_meta/3]).

with_meta(Event, Seq, Ts) when is_map(Event) -> Event#{seq => Seq, ts => Ts};
with_meta(Event, Seq, Ts) -> #{type => <<"unknown">>, value => Event, seq => Seq, ts => Ts}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
