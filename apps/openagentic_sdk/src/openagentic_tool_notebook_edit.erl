-module(openagentic_tool_notebook_edit).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"NotebookEdit">>.

description() -> <<"Edit a Jupyter notebook (.ipynb).">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),

  NotebookPath0 = maps:get(<<"notebook_path">>, Input, maps:get(notebook_path, Input, undefined)),
  case NotebookPath0 of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'notebook_path' must be a non-empty string">>}};
    _ ->
      NotebookPath = to_bin(NotebookPath0),
      case byte_size(string:trim(NotebookPath)) > 0 of
        false -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'notebook_path' must be a non-empty string">>}};
        true ->
          case openagentic_fs:resolve_tool_path(ProjectDir, NotebookPath) of
            {error, Reason} ->
              {error, Reason};
            {ok, FullPath0} ->
              FullPath = ensure_list(FullPath0),
              case filelib:is_regular(FullPath) of
                false ->
                  Msg = iolist_to_binary([<<"NotebookEdit: not found: ">>, openagentic_fs:norm_abs_bin(FullPath)]),
                  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
                true -> edit_notebook(FullPath, Input)
              end
          end
      end
  end.

edit_notebook(FullPath, Input) ->
  CellId0 = trim_non_empty(maps:get(<<"cell_id">>, Input, maps:get(cell_id, Input, undefined))),
  NewSource = to_bin(maps:get(<<"new_source">>, Input, maps:get(new_source, Input, <<"">>))),
  CellType0 = trim_non_empty(maps:get(<<"cell_type">>, Input, maps:get(cell_type, Input, undefined))),
  EditMode0 = to_bin(maps:get(<<"edit_mode">>, Input, maps:get(edit_mode, Input, <<"replace">>))),
  EditMode = string:lowercase(string:trim(EditMode0)),

  case CellType0 of
    undefined -> ok;
    <<"code">> -> ok;
    <<"markdown">> -> ok;
    _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'cell_type' must be 'code' or 'markdown'">>})
  end,
  case lists:member(EditMode, [<<"replace">>, <<"insert">>, <<"delete">>]) of
    true -> ok;
    false -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'edit_mode' must be 'replace', 'insert', or 'delete'">>})
  end,

  try
    {ok, Raw} = file:read_file(FullPath),
    Nb0 =
      try openagentic_json:decode(Raw)
      catch
        _:_ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid notebook json">>})
      end,
    Nb = ensure_map(Nb0),
    CellsEl = maps:get(<<"cells">>, Nb, undefined),
    Cells =
      case CellsEl of
        L when is_list(L) -> L;
        _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid notebook: missing 'cells' list">>})
      end,

    Idx = find_index(Cells, CellId0),
    case EditMode of
      <<"delete">> ->
        case Idx of
          undefined -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: cell_id not found">>});
          I ->
            {Deleted, Cells2} = remove_at(Cells, I),
            DeletedId = extract_id(Deleted),
            Nb2 = Nb#{<<"cells">> => Cells2},
            ok = write_notebook(FullPath, Nb2),
            {ok, #{
              message => <<"Deleted cell">>,
              edit_type => <<"deleted">>,
              cell_id => maybe_null(DeletedId),
              total_cells => length(Cells2)
            }}
        end;
      <<"insert">> ->
        NewId =
          case CellId0 of
            undefined -> random_hex(16);
            CellIdVal -> binary_to_list(CellIdVal)
          end,
        CellType = case CellType0 of undefined -> <<"code">>; CellTypeVal -> CellTypeVal end,
        Cell = #{
          <<"cell_type">> => CellType,
          <<"metadata">> => #{},
          <<"source">> => normalize_source(NewSource),
          <<"id">> => to_bin(NewId)
        },
        InsertAt =
          case Idx of
            undefined -> length(Cells);
            I -> erlang:min(I + 1, length(Cells))
          end,
        Cells2 = insert_at(Cells, InsertAt, Cell),
        Nb2 = Nb#{<<"cells">> => Cells2},
        ok = write_notebook(FullPath, Nb2),
        {ok, #{
          message => <<"Inserted cell">>,
          edit_type => <<"inserted">>,
          cell_id => to_bin(NewId),
          total_cells => length(Cells2)
        }};
      _ ->
        %% replace
        case Idx of
          undefined -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: cell_id not found">>});
          I ->
            Cell0 = lists:nth(I + 1, Cells),
            CellMap =
              case Cell0 of
                M when is_map(M) -> M;
                _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: invalid cell">>})
              end,
            CellMap2 =
              case CellType0 of
                undefined -> CellMap;
                CellTypeVal2 -> CellMap#{<<"cell_type">> => CellTypeVal2}
              end,
            CellMap3 = CellMap2#{<<"source">> => normalize_source(NewSource)},
            ReplacedId = extract_id(CellMap3),
            Cells2 = replace_at(Cells, I, CellMap3),
            Nb2 = Nb#{<<"cells">> => Cells2},
            ok = write_notebook(FullPath, Nb2),
            {ok, #{
              message => <<"Replaced cell">>,
              edit_type => <<"replaced">>,
              cell_id => maybe_null(ReplacedId),
              total_cells => length(Cells2)
            }}
        end
    end
  catch
    throw:Reason ->
      {error, Reason};
    C:R ->
      {error, {C, R}}
  end.

find_index([], _CellId) -> undefined;
find_index(Cells, undefined) ->
  case Cells of
    [] -> undefined;
    _ -> 0
  end;
find_index(Cells, CellId) ->
  find_index2(Cells, CellId, 0).

find_index2([], _CellId, _I) -> undefined;
find_index2([H | T], CellId, I) ->
  Obj = ensure_map(H),
  case maps:get(<<"id">>, Obj, undefined) of
    V when is_binary(V) ->
      case V =:= CellId of
        true -> I;
        false -> find_index2(T, CellId, I + 1)
      end;
    _ ->
      find_index2(T, CellId, I + 1)
  end.

extract_id(Obj0) ->
  Obj = ensure_map(Obj0),
  case maps:get(<<"id">>, Obj, undefined) of
    V when is_binary(V) -> V;
    V when is_list(V) -> to_bin(V);
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

write_notebook(FullPath, Nb) ->
  Bin = openagentic_json:encode(Nb),
  file:write_file(FullPath, <<Bin/binary, "\n">>).

remove_at(List, Index) ->
  {Head, [H | Tail]} = lists:split(Index, List),
  {H, Head ++ Tail}.

replace_at(List, Index, Val) ->
  {Head, [_ | Tail]} = lists:split(Index, List),
  Head ++ [Val] ++ Tail.

insert_at(List, Index, Val) ->
  {Head, Tail} = lists:split(Index, List),
  Head ++ [Val] ++ Tail.

trim_non_empty(undefined) -> undefined;
trim_non_empty(V0) ->
  V = to_bin(V0),
  case byte_size(string:trim(V)) > 0 of
    true -> V;
    false -> undefined
  end.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

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
