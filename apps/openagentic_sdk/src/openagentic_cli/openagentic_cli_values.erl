-module(openagentic_cli_values).
-export([cwd_safe/0,first_non_blank/1,strip_wrapping_quotes/1,to_bool_default/2,ensure_map/1,ensure_list/1,to_bin/1,to_list/1,to_text/1]).

cwd_safe() ->
  case file:get_cwd() of
    {ok, V} -> V;
    _ -> "."
  end.

first_non_blank([]) ->
  undefined;
first_non_blank([false | Rest]) ->
  %% os:getenv/1 returns the atom `false` when unset; treat as missing.
  first_non_blank(Rest);
first_non_blank([undefined | Rest]) ->
  first_non_blank(Rest);
first_non_blank([null | Rest]) ->
  first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V1 = strip_wrapping_quotes(to_bin(V0)),
  case byte_size(string:trim(V1)) > 0 of
    true -> string:trim(V1);
    false -> first_non_blank(Rest)
  end.

strip_wrapping_quotes(Val0) ->
  Val = string:trim(to_bin(Val0)),
  case byte_size(Val) >= 2 of
    false ->
      Val;
    true ->
      First = binary:at(Val, 0),
      Last = binary:at(Val, byte_size(Val) - 1),
      case {First, Last} of
        {$", $"} -> string:trim(binary:part(Val, 1, byte_size(Val) - 2));
        {$', $'} -> string:trim(binary:part(Val, 1, byte_size(Val) - 2));
        _ -> Val
      end
  end.

to_bool_default(undefined, Default) -> Default;
to_bool_default(null, Default) -> Default;
to_bool_default(true, _Default) -> true;
to_bool_default(false, _Default) -> false;
to_bool_default(1, _Default) -> true;
to_bool_default(0, _Default) -> false;
to_bool_default(V, Default) ->
  S = string:lowercase(string:trim(to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"allow">> -> true;
    <<"ok">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [binary_to_list(B)];
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) ->
  %% Some callers provide UTF-8 bytes as a list of integers (iolist); others provide Unicode codepoints.
  %% Prefer treating lists as raw bytes when possible to avoid double-encoding ("è¿..." mojibake).
  try
    iolist_to_binary(L)
  catch
    _:_ -> unicode:characters_to_binary(L, utf8)
  end;
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_text(B) when is_binary(B) ->
  %% Decode UTF-8 bytes into Unicode codepoints for "~ts" formatting.
  try
    unicode:characters_to_list(B, utf8)
  catch
    _:_ -> binary_to_list(B)
  end;
to_text(L) when is_list(L) -> L;
to_text(A) when is_atom(A) -> atom_to_list(A);
to_text(Other) -> lists:flatten(io_lib:format("~p", [Other])).
