-module(openagentic_tool_notebook_edit_ops).

-export([edit_notebook/2]).

edit_notebook(FullPath, Input) ->
  CellId0 = openagentic_tool_notebook_edit_utils:trim_non_empty(maps:get(<<"cell_id">>, Input, maps:get(cell_id, Input, undefined))),
  NewSource = openagentic_tool_notebook_edit_utils:to_bin(maps:get(<<"new_source">>, Input, maps:get(new_source, Input, <<"">>))),
  CellType0 = openagentic_tool_notebook_edit_utils:trim_non_empty(maps:get(<<"cell_type">>, Input, maps:get(cell_type, Input, undefined))),
  EditMode0 = openagentic_tool_notebook_edit_utils:to_bin(maps:get(<<"edit_mode">>, Input, maps:get(edit_mode, Input, <<"replace">>))),
  EditMode = string:lowercase(string:trim(EditMode0)),
  validate_cell_type(CellType0),
  validate_edit_mode(EditMode),
  try
    {ok, Raw} = file:read_file(FullPath),
    Nb0 = try openagentic_json:decode(Raw) catch _:_ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid notebook json">>}) end,
    Nb = openagentic_tool_notebook_edit_utils:ensure_map(Nb0),
    CellsEl = maps:get(<<"cells">>, Nb, undefined),
    Cells = case CellsEl of L when is_list(L) -> L; _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid notebook: missing 'cells' list">>}) end,
    Idx = openagentic_tool_notebook_edit_cells:find_index(Cells, CellId0),
    apply_edit_mode(EditMode, Nb, Cells, Idx, CellId0, CellType0, NewSource, FullPath)
  catch
    throw:Reason -> {error, Reason};
    C:R -> {error, {C, R}}
  end.

validate_cell_type(undefined) -> ok;
validate_cell_type(<<"code">>) -> ok;
validate_cell_type(<<"markdown">>) -> ok;
validate_cell_type(_) -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'cell_type' must be 'code' or 'markdown'">>}).

validate_edit_mode(EditMode) ->
  case lists:member(EditMode, [<<"replace">>, <<"insert">>, <<"delete">>]) of
    true -> ok;
    false -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'edit_mode' must be 'replace', 'insert', or 'delete'">>})
  end.

apply_edit_mode(<<"delete">>, Nb, Cells, Idx, _CellId0, _CellType0, _NewSource, FullPath) ->
  case Idx of
    undefined -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: cell_id not found">>});
    I ->
      {Deleted, Cells2} = openagentic_tool_notebook_edit_cells:remove_at(Cells, I),
      DeletedId = openagentic_tool_notebook_edit_cells:extract_id(Deleted),
      write_result(FullPath, Nb#{<<"cells">> => Cells2}, <<"Deleted cell">>, <<"deleted">>, DeletedId, length(Cells2))
  end;
apply_edit_mode(<<"insert">>, Nb, Cells, Idx, CellId0, CellType0, NewSource, FullPath) ->
  NewId = case CellId0 of undefined -> openagentic_tool_notebook_edit_utils:random_hex(16); CellIdVal -> binary_to_list(CellIdVal) end,
  CellType = case CellType0 of undefined -> <<"code">>; CellTypeVal -> CellTypeVal end,
  Cell = #{
    <<"cell_type">> => CellType,
    <<"metadata">> => #{},
    <<"source">> => openagentic_tool_notebook_edit_cells:normalize_source(NewSource),
    <<"id">> => openagentic_tool_notebook_edit_utils:to_bin(NewId)
  },
  InsertAt = case Idx of undefined -> length(Cells); I -> erlang:min(I + 1, length(Cells)) end,
  Cells2 = openagentic_tool_notebook_edit_cells:insert_at(Cells, InsertAt, Cell),
  write_result(FullPath, Nb#{<<"cells">> => Cells2}, <<"Inserted cell">>, <<"inserted">>, openagentic_tool_notebook_edit_utils:to_bin(NewId), length(Cells2));
apply_edit_mode(_Replace, Nb, Cells, Idx, _CellId0, CellType0, NewSource, FullPath) ->
  case Idx of
    undefined -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: cell_id not found">>});
    I ->
      Cell0 = lists:nth(I + 1, Cells),
      CellMap = case Cell0 of M when is_map(M) -> M; _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid cell">>}) end,
      CellMap2 = case CellType0 of undefined -> CellMap; CellTypeVal2 -> CellMap#{<<"cell_type">> => CellTypeVal2} end,
      CellMap3 = CellMap2#{<<"source">> => openagentic_tool_notebook_edit_cells:normalize_source(NewSource)},
      ReplacedId = openagentic_tool_notebook_edit_cells:extract_id(CellMap3),
      Cells2 = openagentic_tool_notebook_edit_cells:replace_at(Cells, I, CellMap3),
      write_result(FullPath, Nb#{<<"cells">> => Cells2}, <<"Replaced cell">>, <<"replaced">>, ReplacedId, length(Cells2))
  end.

write_result(FullPath, Nb, Message, EditType, CellId, TotalCells) ->
  Bin = openagentic_json:encode(Nb),
  ok = file:write_file(FullPath, <<Bin/binary, "\n">>),
  {ok, #{
    message => Message,
    edit_type => EditType,
    cell_id => openagentic_tool_notebook_edit_cells:maybe_null(CellId),
    total_cells => TotalCells
  }}.
