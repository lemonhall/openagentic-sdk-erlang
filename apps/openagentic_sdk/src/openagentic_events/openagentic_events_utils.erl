-module(openagentic_events_utils).
-export([bool_true/1, drop_undefined/1, ensure_map/1, to_bin/1, to_int/1]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

drop_undefined(M) when is_map(M) -> maps:from_list([{K, V} || {K, V} <- maps:to_list(M), V =/= undefined]);
drop_undefined(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(F) when is_float(F) -> iolist_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

to_int(I) when is_integer(I) -> I;
to_int(B) when is_binary(B) -> case catch binary_to_integer(string:trim(B)) of I when is_integer(I) -> I; _ -> 0 end;
to_int(L) when is_list(L) -> case catch list_to_integer(string:trim(L)) of I when is_integer(I) -> I; _ -> 0 end;
to_int(_) -> 0.

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of <<"true">> -> true; <<"1">> -> true; <<"yes">> -> true; <<"y">> -> true; _ -> false end;
bool_true(L) when is_list(L) -> bool_true(unicode:characters_to_binary(L, utf8));
bool_true(I) when is_integer(I) -> I =/= 0;
bool_true(_) -> false.
