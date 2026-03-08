-module(openagentic_tool_lsp_utils).

-export([string_list_non_empty/1, string_list_allow_empty/1, string_map/1, first_non_empty/2, int_opt/3, ends_with/2, ensure_map/1, ensure_list/1, to_bin/1, bin_to_utf8/1]).

string_list_non_empty(Val) ->
  case Val of
    L when is_list(L), L =/= [] ->
      List = [to_bin(X) || X <- L, byte_size(string:trim(to_bin(X))) > 0],
      case length(List) =:= length(L) of
        true -> List;
        false -> undefined
      end;
    _ ->
      undefined
  end.

string_list_allow_empty(Val) ->
  case Val of
    L when is_list(L) ->
      List = [to_bin(X) || X <- L],
      case lists:any(fun (B) -> byte_size(string:trim(to_bin(B))) =:= 0 end, List) of
        true -> undefined;
        false -> List
      end;
    _ ->
      undefined
  end.

string_map(undefined) -> undefined;
string_map(Obj) when is_map(Obj) ->
  maps:from_list(
    [{to_bin(K), to_bin(V)} || {K, V} <- maps:to_list(Obj)]
  );
string_map(_) -> undefined.

first_non_empty(_Map, []) -> undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
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
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of X when is_integer(X) -> X; _ -> Default end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of X when is_integer(X) -> X; _ -> Default end;
    _ -> Default
  end.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bin_to_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end.
