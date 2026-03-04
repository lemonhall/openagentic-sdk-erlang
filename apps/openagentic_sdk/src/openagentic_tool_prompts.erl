-module(openagentic_tool_prompts).

-export([render/2]).

render(Name0, Vars0) ->
  Name = to_bin(Name0),
  Vars1 = ensure_map(Vars0),
  Vars = Vars1#{date => iso_date()},
  Tpl = template(Name),
  string:trim(apply_vars(Tpl, Vars)).

template(Name0) ->
  Name = normalize_name(Name0),
  Priv = code:priv_dir(openagentic_sdk),
  Path = filename:join([Priv, "toolprompts", binary_to_list(Name) ++ ".txt"]),
  case file:read_file(Path) of
    {ok, Bin} -> normalize_newlines(Bin);
    _ -> <<>>
  end.

apply_vars(Tpl, Vars) ->
  Pairs = maps:to_list(Vars),
  lists:foldl(
    fun ({K0, V0}, Acc0) ->
      K = to_bin(K0),
      V = to_bin(V0),
      Key = iolist_to_binary([<<"{{">>, K, <<"}}">>]),
      Key2 = iolist_to_binary([<<"${">>, K, <<"}">>]),
      Acc1 = binary:replace(Acc0, Key, V, [global]),
      binary:replace(Acc1, Key2, V, [global])
    end,
    to_bin(Tpl),
    Pairs
  ).

normalize_name(Bin0) ->
  Bin = to_bin(Bin0),
  string:lowercase(string:trim(Bin)).

normalize_newlines(Bin0) when is_binary(Bin0) ->
  Bin1 = binary:replace(Bin0, <<"\r\n">>, <<"\n">>, [global]),
  binary:replace(Bin1, <<"\r">>, <<"\n">>, [global]).

iso_date() ->
  {{Y, M, D}, _} = calendar:local_time(),
  iolist_to_binary(io_lib:format("~4..0b-~2..0b-~2..0b", [Y, M, D])).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
