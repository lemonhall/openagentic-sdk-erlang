-module(openagentic_tool_list).

-include_lib("kernel/include/file.hrl").

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"List">>.

description() -> <<"List files under a directory.">>.

-define(DEFAULT_LIMIT, 100).

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  Raw =
    first_non_empty(Input, [
      <<"path">>, path,
      <<"dir">>, dir,
      <<"directory">>, directory
    ]),
  case Raw of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"List: 'path' must be a non-empty string">>}};
    _ ->
      case openagentic_fs:resolve_tool_path(ProjectDir, Raw) of
        {error, Reason} ->
          {error, Reason};
        {ok, BaseDir0} ->
          BaseDir = ensure_list(BaseDir0),
          case file:read_file_info(BaseDir) of
            {error, _} ->
              Msg = iolist_to_binary([<<"List: not found: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
              {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
            {ok, Info} when Info#file_info.type =/= directory ->
              Msg = iolist_to_binary([<<"List: not a directory: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
              {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
            {ok, _Info} ->
              Lim = ?DEFAULT_LIMIT,
              {FilesPlusOne, Truncated} = collect_files(BaseDir, Lim + 1),
              Files0 = case Truncated of true -> lists:sublist(FilesPlusOne, Lim); false -> FilesPlusOne end,
              Files = lists:reverse(Files0),
              Rendered = render_tree(BaseDir, Files),
              {ok, #{
                path => openagentic_fs:norm_abs_bin(BaseDir),
                count => length(Files),
                truncated => Truncated,
                output => Rendered
              }}
          end
      end
  end.

%% internal
collect_files(Root, Limit) ->
  collect_dir(Root, [], Root, Limit, []).

collect_dir(_Dir, _RelSegs, _Root, Limit, Acc) when length(Acc) >= Limit ->
  {Acc, true};
collect_dir(Dir, RelSegs, Root, Limit, Acc0) ->
  case should_ignore(RelSegs) of
    true ->
      {Acc0, length(Acc0) >= Limit};
    false ->
      Children =
        case file:list_dir(Dir) of
          {ok, Names} -> lists:sort(Names);
          _ -> []
        end,
      lists:foldl(
        fun (Name0, {Acc1, Trunc1}) ->
          case Trunc1 of
            true ->
              {Acc1, true};
            false ->
              Name = ensure_list(Name0),
              Full = filename:join([Dir, Name]),
              Rel = RelSegs ++ [Name],
              case should_ignore(Rel) of
                true ->
                  {Acc1, false};
                false ->
                  case filelib:is_dir(Full) of
                    true ->
                      collect_dir(Full, Rel, Root, Limit, Acc1);
                    false ->
                      case length(Acc1) + 1 >= Limit of
                        true -> {[Rel | Acc1], true};
                        false -> {[Rel | Acc1], false}
                      end
                  end
              end
          end
        end,
        {Acc0, false},
        Children
      )
  end.

should_ignore([]) -> false;
should_ignore(Segs) ->
  lists:any(fun (S) -> lists:member(S, ignore_prefixes()) end, Segs).

ignore_prefixes() ->
  [
    "node_modules",
    "__pycache__",
    ".git",
    "dist",
    "build",
    "target",
    "vendor",
    ".idea",
    ".vscode",
    ".venv",
    "venv",
    "env",
    ".cache",
    "coverage",
    "tmp",
    "temp"
  ].

render_tree(Root, RelFiles0) ->
  RelFiles = RelFiles0,
  %% Build dirs and files by dir.
  {Dirs, FilesByDir} = build_tree(RelFiles),
  RootLine = iolist_to_binary([to_bin(norm_path(Root)), <<"/\n">>]),
  iolist_to_binary([RootLine, render_dir([], 0, Dirs, FilesByDir)]).

build_tree(RelFiles) ->
  Dirs0 = ordsets:from_list([[]]),
  {Dirs, FilesByDir} =
    lists:foldl(
      fun (Segs, {DirsAcc0, Map0}) ->
        DirParts = case Segs of [_] -> []; _ -> lists:sublist(Segs, length(Segs) - 1) end,
        DirsAcc1 = add_prefixes(DirsAcc0, DirParts),
        FileName = lists:last(Segs),
        Map1 = maps:update_with(DirParts, fun (L) -> [FileName | L] end, [FileName], Map0),
        {DirsAcc1, Map1}
      end,
      {Dirs0, #{}},
      RelFiles
    ),
  {Dirs, FilesByDir}.

add_prefixes(Dirs, Parts) ->
  lists:foldl(
    fun (I, Acc) ->
      ordsets:add_element(lists:sublist(Parts, I), Acc)
    end,
    Dirs,
    lists:seq(0, length(Parts))
  ).

render_dir(Prefix, Depth, Dirs, FilesByDir) ->
  Indent = lists:duplicate(Depth * 2, $\s),
  Line =
    case {Depth, Prefix} of
      {0, _} -> <<>>;
      {_, []} -> <<>>;
      _ -> iolist_to_binary([Indent, lists:last(Prefix), <<"/\n">>])
    end,
  Children =
    lists:sort(
      [D || D <- ordsets:to_list(Dirs), length(D) =:= length(Prefix) + 1, lists:prefix(Prefix, D)]
    ),
  ChildrenRendered = [render_dir(D, Depth + 1, Dirs, FilesByDir) || D <- Children],
  FileNames = lists:sort(maps:get(Prefix, FilesByDir, [])),
  FileIndent = lists:duplicate((Depth + 1) * 2, $\s),
  FilesRendered = [iolist_to_binary([FileIndent, F, <<"\n">>]) || F <- FileNames],
  iolist_to_binary([Line, ChildrenRendered, FilesRendered]).

first_non_empty(_Map, []) ->
  undefined;
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

norm_path(Path0) ->
  Path = ensure_list(Path0),
  lists:flatten(string:replace(Path, "\\", "/", all)).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
