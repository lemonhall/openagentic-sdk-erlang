-module(openagentic_tool_notebook_edit_cells).

-export([find_index/2, extract_id/1, maybe_null/1, normalize_source/1, remove_at/2, replace_at/3, insert_at/3]).

find_index([], _CellId) -> undefined;
find_index(Cells, undefined) ->
  case Cells of [] -> undefined; _ -> 0 end;
find_index(Cells, CellId) ->
  find_index2(Cells, CellId, 0).

find_index2([], _CellId, _I) -> undefined;
find_index2([H | T], CellId, I) ->
  Obj = openagentic_tool_notebook_edit_utils:ensure_map(H),
  case maps:get(<<"id">>, Obj, undefined) of
    V when is_binary(V) ->
      case V =:= CellId of true -> I; false -> find_index2(T, CellId, I + 1) end;
    _ ->
      find_index2(T, CellId, I + 1)
  end.

extract_id(Obj0) ->
  Obj = openagentic_tool_notebook_edit_utils:ensure_map(Obj0),
  case maps:get(<<"id">>, Obj, undefined) of
    V when is_binary(V) -> V;
    V when is_list(V) -> openagentic_tool_notebook_edit_utils:to_bin(V);
    _ -> undefined
  end.

maybe_null(undefined) -> null;
maybe_null(V) -> V.

normalize_source(NewSource) ->
  case NewSource of
    <<>> -> [<<"">>];
    _ ->
      case binary:match(NewSource, <<"\n">>) of
        nomatch -> [NewSource];
        _ ->
          Parts = binary:split(NewSource, <<"\n">>, [global]),
          [<<P/binary, "\n">> || P <- Parts]
      end
  end.

remove_at(List, Index) ->
  {Head, [H | Tail]} = lists:split(Index, List),
  {H, Head ++ Tail}.

replace_at(List, Index, Val) ->
  {Head, [_ | Tail]} = lists:split(Index, List),
  Head ++ [Val] ++ Tail.

insert_at(List, Index, Val) ->
  {Head, Tail} = lists:split(Index, List),
  Head ++ [Val] ++ Tail.
