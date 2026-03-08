-module(openagentic_tool_list_render).

-export([render_tree/2]).

render_tree(Root, RelFiles) ->
  {Dirs, FilesByDir} = build_tree(RelFiles),
  RootLine = iolist_to_binary([openagentic_tool_list_utils:to_bin(norm_path(Root)), <<"/\n">>]),
  iolist_to_binary([RootLine, render_dir([], 0, Dirs, FilesByDir)]).

build_tree(RelFiles) ->
  Dirs0 = ordsets:from_list([[]]),
  lists:foldl(
    fun (Segs, {DirsAcc0, Map0}) ->
      DirParts = case Segs of [_] -> []; _ -> lists:sublist(Segs, length(Segs) - 1) end,
      DirsAcc1 = add_prefixes(DirsAcc0, DirParts),
      FileName = lists:last(Segs),
      {DirsAcc1, maps:update_with(DirParts, fun (L) -> [FileName | L] end, [FileName], Map0)}
    end,
    {Dirs0, #{}},
    RelFiles
  ).

add_prefixes(Dirs, Parts) ->
  lists:foldl(fun (I, Acc) -> ordsets:add_element(lists:sublist(Parts, I), Acc) end, Dirs, lists:seq(0, length(Parts))).

render_dir(Prefix, Depth, Dirs, FilesByDir) ->
  Indent = lists:duplicate(Depth * 2, $\s),
  Line =
    case {Depth, Prefix} of
      {0, _} -> <<>>;
      {_, []} -> <<>>;
      _ -> iolist_to_binary([Indent, lists:last(Prefix), <<"/\n">>])
    end,
  Children = lists:sort([D || D <- ordsets:to_list(Dirs), length(D) =:= length(Prefix) + 1, lists:prefix(Prefix, D)]),
  ChildrenRendered = [render_dir(D, Depth + 1, Dirs, FilesByDir) || D <- Children],
  FileNames = lists:sort(maps:get(Prefix, FilesByDir, [])),
  FileIndent = lists:duplicate((Depth + 1) * 2, $\s),
  FilesRendered = [iolist_to_binary([FileIndent, F, <<"\n">>]) || F <- FileNames],
  iolist_to_binary([Line, ChildrenRendered, FilesRendered]).

norm_path(Path0) ->
  Path = openagentic_tool_list_utils:ensure_list(Path0),
  lists:flatten(string:replace(Path, "\\", "/", all)).
