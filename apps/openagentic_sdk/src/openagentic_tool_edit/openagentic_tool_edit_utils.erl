-module(openagentic_tool_edit_utils).

-export([
  string_opt/1,
  first_value/2,
  int_opt/3,
  ensure_map/1,
  ensure_list/1,
  to_bin/1,
  is_sensitive_basename/1,
  bool_true/1
]).

string_opt(undefined) -> undefined;
string_opt(V0) ->
  case is_stringy(V0) of
    false -> undefined;
    true ->
      V = to_bin(V0),
      case byte_size(string:trim(V)) > 0 of true -> V; false -> undefined end
  end.

first_value(_Map, []) ->
  undefined;
first_value(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_value(Map, Rest);
    V -> V
  end.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) -> parse_int_bin(B, Default);
    L when is_list(L) -> parse_int_list(L, Default);
    _ -> Default
  end.

parse_int_bin(Bin, Default) ->
  case (catch binary_to_integer(string:trim(Bin))) of
    X when is_integer(X) -> X;
    _ -> Default
  end.

parse_int_list(List, Default) ->
  case (catch list_to_integer(string:trim(List))) of
    X when is_integer(X) -> X;
    _ -> Default
  end.

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

is_sensitive_basename(Path0) ->
  Path = ensure_list(Path0),
  Base = string:lowercase(filename:basename(string:trim(Path))),
  case Base of
    ".env" -> true;
    "id_rsa" -> true;
    "id_ed25519" -> true;
    _ ->
      case lists:prefix(".env.", Base) of
        true -> Base =/= ".env.example";
        false ->
          Ext = string:lowercase(filename:extension(Base)),
          lists:member(Ext, [".pem", ".key", ".p12", ".pfx"])
      end
  end.

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of
    <<"true">> -> true;
    <<"1">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    _ -> false
  end;
bool_true(L) when is_list(L) ->
  bool_true(unicode:characters_to_binary(L, utf8));
bool_true(_) ->
  false.

is_stringy(undefined) -> false;
is_stringy(B) when is_binary(B) -> true;
is_stringy(L) when is_list(L) -> true;
is_stringy(_) -> false.
