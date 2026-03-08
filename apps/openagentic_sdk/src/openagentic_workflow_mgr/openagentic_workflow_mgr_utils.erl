-module(openagentic_workflow_mgr_utils).
-export([clamp_int/3, ensure_list/1, ensure_list_value/1, ensure_map/1, int_or_default/2, now_ms/0, to_bin/1]).

now_ms() -> erlang:monotonic_time(millisecond).

clamp_int(I, Min, Max) when is_integer(I) -> erlang:min(Max, erlang:max(Min, I));
clamp_int(_Other, Min, _Max) -> Min.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) -> case catch binary_to_integer(string:trim(B)) of I when is_integer(I) -> I; _ -> Default end;
    L when is_list(L) -> case catch list_to_integer(string:trim(L)) of I when is_integer(I) -> I; _ -> Default end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(_) -> [].

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
