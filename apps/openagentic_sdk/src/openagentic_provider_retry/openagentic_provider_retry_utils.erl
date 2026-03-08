-module(openagentic_provider_retry_utils).

-export([bool_default/3, ensure_int/2, ensure_list/1, ensure_map/1, int_default/3, now_ms/0, sleep_ms/1, to_bin/1]).

now_ms() ->
  erlang:system_time(millisecond).

sleep_ms(Ms) ->
  timer:sleep(Ms),
  ok.

ensure_int(I, _Default) when is_integer(I) -> I;
ensure_int(B, Default) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of X when is_integer(X) -> X; _ -> Default end;
ensure_int(L, Default) when is_list(L) ->
  ensure_int(unicode:characters_to_binary(L, utf8), Default);
ensure_int(_, Default) ->
  Default.

int_default(Map, Keys, Default) ->
  ensure_int(find_first(Map, Keys), Default).

bool_default(Map, Keys, Default) ->
  case find_first(Map, Keys) of
    undefined -> Default;
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    Val -> lists:member(string:lowercase(string:trim(to_bin(Val))), [<<"true">>, <<"1">>, <<"yes">>, <<"y">>, <<"ok">>])
  end.

find_first(Map, Keys) ->
  lists:foldl(fun (K, Acc) -> case Acc of undefined -> maps:get(K, Map, undefined); _ -> Acc end end, undefined, Keys).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
