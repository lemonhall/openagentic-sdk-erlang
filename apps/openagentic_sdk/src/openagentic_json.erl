-module(openagentic_json).

-export([encode/1, encode_safe/1, to_json_term/1, decode/1]).

encode(Map) ->
  jsone:encode(Map).

%% encode_safe/1 is for persistence/UI only (session store, web responses).
%% It defensively converts common Erlang terms into JSON-safe values:
%% - drops map keys with value `undefined`
%% - converts `undefined` to null (when it appears in lists)
%% - converts pid/ref/fun/port/tuple/etc. to a printable string
%% - converts non-UTF8 binaries to a printable string
encode_safe(Term) ->
  jsone:encode(to_json_term(Term)).

to_json_term(Term) ->
  sanitize(Term).

decode(Bin) when is_binary(Bin) ->
  jsone:decode(Bin, [{object_format, map}]).

%% ---- internal ----

sanitize(undefined) -> null;
sanitize(null) -> null;
sanitize(true) -> true;
sanitize(false) -> false;
sanitize(I) when is_integer(I) -> I;
sanitize(F) when is_float(F) -> F;
sanitize(B) when is_binary(B) ->
  %% jsone treats binaries as strings (UTF-8). If the bytes are not UTF-8, stringify.
  case unicode:characters_to_list(B, utf8) of
    L when is_list(L) ->
      B;
    _ ->
      iolist_to_binary(io_lib:format("~p", [B]))
  end;
sanitize(A) when is_atom(A) ->
  atom_to_binary(A, utf8);
sanitize(P) when is_pid(P) ->
  iolist_to_binary(io_lib:format("~p", [P]));
sanitize(R) when is_reference(R) ->
  iolist_to_binary(io_lib:format("~p", [R]));
sanitize(Port) when is_port(Port) ->
  iolist_to_binary(io_lib:format("~p", [Port]));
sanitize(Fun) when is_function(Fun) ->
  iolist_to_binary(io_lib:format("~p", [Fun]));
sanitize(M) when is_map(M) ->
  maps:from_list(
    [
      {K, sanitize(V)}
      || {K, V} <- maps:to_list(M),
         V =/= undefined
    ]
  );
sanitize(L) when is_list(L) ->
  case is_flat_charlist(L) of
    true ->
      %% Treat plain Erlang strings (lists of integers) as JSON strings.
      try
        unicode:characters_to_binary(L, utf8)
      catch
        _:_ -> [sanitize(X) || X <- L]
      end;
    false ->
      [sanitize(X) || X <- L]
  end;
sanitize(T) when is_tuple(T) ->
  iolist_to_binary(io_lib:format("~p", [T]));
sanitize(Other) ->
  iolist_to_binary(io_lib:format("~p", [Other])).

is_flat_charlist([]) -> false;
is_flat_charlist([H | T]) when is_integer(H) -> is_flat_charlist(T);
is_flat_charlist(_) -> false.
