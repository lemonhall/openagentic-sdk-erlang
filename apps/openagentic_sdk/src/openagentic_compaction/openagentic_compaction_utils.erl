-module(openagentic_compaction_utils).
-export([bool_default/3, bool_true/1, ensure_int/2, ensure_list/1, ensure_map/1, int_default/3, int_or_undef/2, safe_json_dumps/1, to_bin/1]).

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

ensure_int(I, _Default) when is_integer(I) -> I;
ensure_int(B, Default) when is_binary(B) -> case catch binary_to_integer(string:trim(B)) of X when is_integer(X) -> X; _ -> Default end;
ensure_int(L, Default) when is_list(L) -> ensure_int(unicode:characters_to_binary(L, utf8), Default);
ensure_int(_, Default) -> Default.

int_default(Map, Keys, Default) ->
  ensure_int(lists:foldl(fun (K, Acc) -> case Acc of undefined -> maps:get(K, Map, undefined); _ -> Acc end end, undefined, Keys), Default).

int_or_undef(Map, Keys) ->
  case lists:foldl(fun (K, Acc) -> case Acc of undefined -> maps:get(K, Map, undefined); _ -> Acc end end, undefined, Keys) of undefined -> undefined; Val -> ensure_int(Val, undefined) end.

bool_default(Map, Keys, Default) ->
  case lists:foldl(fun (K, Acc) -> case Acc of undefined -> maps:get(K, Map, undefined); _ -> Acc end end, undefined, Keys) of
    undefined -> Default;
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    Val -> bool_true(Val)
  end.

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of <<"true">> -> true; <<"1">> -> true; <<"yes">> -> true; <<"y">> -> true; _ -> false end;
bool_true(L) when is_list(L) -> bool_true(unicode:characters_to_binary(L, utf8));
bool_true(I) when is_integer(I) -> I =/= 0;
bool_true(_) -> false.

safe_json_dumps(null) -> "null";
safe_json_dumps(undefined) -> "null";
safe_json_dumps(El) ->
  try binary_to_list(openagentic_json:encode(El)) catch _:_ -> lists:flatten(io_lib:format("~p", [El])) end.
