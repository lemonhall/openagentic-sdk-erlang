-module(openagentic_workflow_dsl_utils).
-export([
  ensure_list/1,
  ensure_map/1,
  err/3,
  get_any/3,
  get_bin/3,
  get_nullable_step_ref/2,
  is_safe_step_id/1,
  maybe_only_keys/5,
  require_list/4,
  require_map/4,
  require_nonempty_bin/4,
  sort_errors/1,
  to_bin/1,
  to_bool_default/2
]).

maybe_only_keys(false, _Map, _Allowed, _Path, Errors) -> Errors;
maybe_only_keys(true, Map, Allowed, Path, Errors0) ->
  Unknown = [K || K <- maps:keys(Map), is_binary(K), not lists:member(K, Allowed)],
  case Unknown of
    [] -> Errors0;
    _ -> [err(Path, <<"unknown_keys">>, iolist_to_binary([<<"unknown keys: ">>, join_binaries(Unknown, <<", ">>)])) | Errors0]
  end.

join_binaries([], _Sep) -> <<>>;
join_binaries([B], _Sep) -> B;
join_binaries([B | Rest], Sep) -> iolist_to_binary([B, Sep, join_binaries(Rest, Sep)]).

get_any(Map, Keys, Default) -> get_any_loop(Map, Keys, Default).

get_any_loop(_Map, [], Default) -> Default;
get_any_loop(Map, [K | Rest], Default) ->
  case maps:find(K, Map) of
    {ok, V} -> V;
    error -> get_any_loop(Map, Rest, Default)
  end.

get_bin(Map, Keys, Default) ->
  case get_any(Map, Keys, Default) of
    B when is_binary(B) -> B;
    L when is_list(L) -> iolist_to_binary(L);
    A when is_atom(A) -> atom_to_binary(A, utf8);
    I when is_integer(I) -> integer_to_binary(I);
    null -> <<>>;
    undefined -> <<>>;
    _ -> Default
  end.

get_nullable_step_ref(Map, Keys) ->
  case get_any(Map, Keys, undefined) of
    null -> null;
    undefined -> undefined;
    B when is_binary(B) -> string:trim(B);
    L when is_list(L) -> string:trim(iolist_to_binary(L));
    A when is_atom(A) -> case A of null -> null; _ -> atom_to_binary(A, utf8) end;
    _ -> undefined
  end.

require_list(_Path, V, _Msg, Errors) when is_list(V) -> {V, Errors};
require_list(Path, _V, Msg, Errors) -> {[], [err(Path, <<"invalid_type">>, Msg) | Errors]}.

require_map(_Path, V, _Msg, Errors) when is_map(V) -> {V, Errors};
require_map(Path, _V, Msg, Errors) -> {#{}, [err(Path, <<"invalid_type">>, Msg) | Errors]}.

require_nonempty_bin(_Path, Bin, _Msg, Errors) when is_binary(Bin), byte_size(Bin) > 0 -> Errors;
require_nonempty_bin(Path, _Bin, Msg, Errors) -> [err(Path, <<"missing">>, Msg) | Errors].

is_safe_step_id(<<>>) -> false;
is_safe_step_id(Id) when is_binary(Id) ->
  case re:run(Id, <<"^[a-z0-9_]+$">>, [{capture, none}]) of
    match -> true;
    _ -> false
  end;
is_safe_step_id(_) -> false.

err(Path0, Code0, Msg0) -> #{path => to_bin(Path0), code => to_bin(Code0), message => to_bin(Msg0)}.

sort_errors(Errors) ->
  lists:sort(fun (A, B) -> maps:get(path, A, <<>>) =< maps:get(path, B, <<>>) end, Errors).

to_bool_default(V0, Default) ->
  case V0 of
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    <<"1">> -> true;
    <<"0">> -> false;
    1 -> true;
    0 -> false;
    _ -> Default
  end.

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
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
