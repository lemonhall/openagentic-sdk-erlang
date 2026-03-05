-module(openagentic_tool_glob).

-include_lib("kernel/include/file.hrl").

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Glob">>.

-define(DEFAULT_MAX_MATCHES, 5000).
-define(DEFAULT_MAX_SCANNED_PATHS, 250000).

description() -> <<"Find files by glob pattern within the project workspace.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir0 = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  Pattern0 = maps:get(<<"pattern">>, Input, maps:get(pattern, Input, undefined)),
  case Pattern0 of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Glob: 'pattern' must be a non-empty string">>}};
    _ ->
      Pattern = ensure_list(Pattern0),
      case byte_size(string:trim(to_bin(Pattern))) > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Glob: 'pattern' must be a non-empty string">>}};
        true ->
          RootRaw0 = first_non_empty(Input, [<<"root">>, root, <<"path">>, path]),
          RootRaw =
            case RootRaw0 of
              undefined -> <<>>;
              _ -> string:trim(to_bin(RootRaw0))
            end,
          BaseRes =
            case byte_size(RootRaw) > 0 of
              true -> openagentic_fs:resolve_read_path(ProjectDir0, WorkspaceDir0, RootRaw);
              false -> openagentic_fs:resolve_read_path(ProjectDir0, WorkspaceDir0, ".")
            end,
          case BaseRes of
            {error, Reason} ->
              {error, Reason};
            {ok, BaseDir0} ->
              BaseDir = ensure_list(BaseDir0),
              case file:read_file_info(BaseDir) of
                {ok, Info} when Info#file_info.type =:= directory ->
                  EarlyExit = should_early_exit_after_first_match(Pattern),
                  MaxMatches = ?DEFAULT_MAX_MATCHES,
                  MaxScanned = ?DEFAULT_MAX_SCANNED_PATHS,
                  Re = openagentic_glob:to_re(Pattern),
                  ScanRoots = resolve_scan_roots(BaseDir, Pattern),
                  BaseNorm = openagentic_fs:norm_abs_bin(BaseDir),
                  case scan_roots(ScanRoots, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, false) of
                    {stop, Matches2, Stop} ->
                      render_stop(BaseDir, Pattern, Matches2, Stop);
                    {ok, Matches0} ->
                      Matches = lists:sort(Matches0),
                      {ok, #{
                        root => BaseNorm,
                        matches => Matches,
                        search_path => BaseNorm,
                        pattern => to_bin(Pattern),
                        count => length(Matches),
                        truncated => false
                      }}
                  end;
                {ok, _Info} ->
                  Msg = iolist_to_binary([<<"Glob: not a directory: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
                  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
                {error, enoent} ->
                  Msg = iolist_to_binary([<<"Glob: not found: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
                  {error, {kotlin_error, <<"FileNotFoundException">>, Msg}};
                {error, E} ->
                  Msg = iolist_to_binary([<<"Glob: cannot access root: ">>, openagentic_fs:norm_abs_bin(BaseDir), <<" error=">>, to_bin(E)]),
                  {error, {kotlin_error, <<"RuntimeException">>, Msg}}
              end
          end
      end
  end.

render_stop(BaseDir, Pattern, Matches0, Stop) ->
  BaseNorm = openagentic_fs:norm_abs_bin(BaseDir),
  Matches = lists:sort(Matches0),
  Count = length(Matches),
  Out0 = #{
    root => BaseNorm,
    matches => Matches,
    pattern => to_bin(Pattern),
    count => Count
  },
  case Stop of
    {max_scanned_paths, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok,
        Out0#{
          search_path => SearchPath,
          truncated => true,
          stopped_early => true,
          early_exit_reason => <<"max_scanned_paths">>
        }};
    {first_match, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok,
        Out0#{
          search_path => SearchPath,
          truncated => true,
          stopped_early => true,
          early_exit_reason => <<"first_match">>
        }};
    {max_matches, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok, Out0#{search_path => SearchPath, truncated => true}}
  end.

scan_roots(ScanRoots, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst) ->
  scan_roots(ScanRoots, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, 0, []).

scan_roots([], _BaseDir, _Re, _MaxMatches, _MaxScanned, _EarlyExit, _WorkspaceFirst, _Scanned, Acc) ->
  {ok, Acc};
scan_roots([Root0 | Rest], BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, Scanned0, Acc0) ->
  Root = ensure_list(Root0),
  case filelib:is_dir(Root) of
    false ->
      scan_roots(Rest, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, Scanned0, Acc0);
    true ->
      case walk_dir(Root, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, Root, Scanned0, Acc0) of
        {ok, Scanned1, Acc1} ->
          scan_roots(Rest, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, Scanned1, Acc1);
        {stop, Acc1, Stop} ->
          {stop, Acc1, Stop}
      end
  end.

walk_dir(_Dir, BaseDir, _Re, _MaxMatches, MaxScanned, _EarlyExit, _WorkspaceFirst, _SearchRoot, Scanned, Acc)
  when Scanned >= MaxScanned ->
  {stop, Acc, {max_scanned_paths, BaseDir}};
walk_dir(Dir, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, Scanned0, Acc0) ->
  Children =
    case file:list_dir(Dir) of
      {ok, Names} -> lists:sort(Names);
      _ -> []
    end,
  lists:foldl(
    fun (Name0, AccIn) ->
      case AccIn of
        {stop, _Acc, _Stop} ->
          AccIn;
        {ok, Scanned1, Acc1} ->
          Name = ensure_list(Name0),
          Full = filename:join([Dir, Name]),
          Scanned2 = Scanned1 + 1,
          case Scanned2 >= MaxScanned of
            true ->
              {stop, Acc1, {max_scanned_paths, BaseDir}};
            false ->
              case filelib:is_dir(Full) of
                true ->
                  walk_dir(Full, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1);
                false ->
                  RelPath = openagentic_glob:relpath(BaseDir, Full),
                  case re:run(RelPath, Re, [{capture, none}]) of
                    match ->
                      MatchPath = openagentic_fs:norm_abs_bin(Full),
                      Acc2 = [MatchPath | Acc1],
                      case EarlyExit of
                        true ->
                          Reason = case WorkspaceFirst of true -> first_match_workspace; false -> first_match end,
                          {stop, lists:reverse([MatchPath]), {Reason, SearchRoot}};
                        false ->
                          case length(Acc2) >= MaxMatches of
                            true -> {stop, Acc2, {max_matches, BaseDir}};
                            false -> {ok, Scanned2, Acc2}
                          end
                      end;
                    nomatch ->
                      {ok, Scanned2, Acc1}
                  end
              end
          end
      end
    end,
    {ok, Scanned0, Acc0},
    Children
  ).

should_early_exit_after_first_match(PatternRaw0) ->
  PatternRaw = ensure_list(PatternRaw0),
  Pattern = string:trim(lists:flatten(string:replace(PatternRaw, "\\", "/", all))),
  Pattern2 =
    case Pattern of
      [$/ | Tail1] -> Tail1;
      _ -> Pattern
    end,
  Components = [C || C <- string:split(Pattern2, "/", all), C =/= ""],
  case Components of
    ["**", Name] ->
      Name2 = string:trim(Name),
      case Name2 of
        "" -> false;
        "**" -> false;
        _ ->
          HasWild = string:find(Name2, "*") =/= nomatch orelse string:find(Name2, "?") =/= nomatch orelse
            string:find(Name2, "[") =/= nomatch,
          case HasWild of
            true -> false;
            false -> string:find(Name2, "/") =:= nomatch
          end
      end;
    _ ->
      false
  end.

resolve_scan_roots(BaseDir0, PatternRaw0) ->
  BaseDir = ensure_list(BaseDir0),
  PatternRaw = ensure_list(PatternRaw0),
  Pattern1 = string:trim(lists:flatten(string:replace(PatternRaw, "\\", "/", all))),
  Pattern2 =
    case Pattern1 of
      [$/ | Tail1] -> Tail1;
      _ -> Pattern1
    end,
  case Pattern2 of
    "" -> [BaseDir];
    "**/*" -> [BaseDir];
    _ ->
      Components = [C || C <- string:split(Pattern2, "/", all), C =/= ""],
      FixedPrefix =
        lists:takewhile(
          fun (Seg) ->
            Seg =/= "**" andalso
              string:find(Seg, "*") =:= nomatch andalso
              string:find(Seg, "?") =:= nomatch andalso
              string:find(Seg, "[") =:= nomatch
          end,
          Components
        ),
      case FixedPrefix of
        [] ->
          [BaseDir];
        _ ->
          PrefixDir = filename:join(FixedPrefix),
          case openagentic_fs:is_safe_rel_path(PrefixDir) of
            false ->
              %% Avoid escaping the project root on Windows (e.g. "C:/Windows/...").
              [BaseDir];
            true ->
              PrefixPath = filename:join([BaseDir, PrefixDir]),
              case filelib:is_dir(PrefixPath) of
                false ->
                  [];
                true ->
                  Remaining = lists:nthtail(length(FixedPrefix), Components),
                  case Remaining of
                    [First, _Second | _] ->
                      IsDirGlob =
                        First =/= "**" andalso
                          (string:find(First, "*") =/= nomatch orelse
                            string:find(First, "?") =/= nomatch orelse
                            string:find(First, "[") =/= nomatch),
                      case IsDirGlob of
                        true ->
                          DirRe = openagentic_glob:to_re(First),
                          Expanded =
                            case file:list_dir(PrefixPath) of
                              {ok, Names} ->
                                [
                                  filename:join([PrefixPath, ensure_list(N)])
                                  || N <- Names,
                                     filelib:is_dir(filename:join([PrefixPath, ensure_list(N)])),
                                     re:run(ensure_list(N), DirRe, [{capture, none}]) =:= match
                                ];
                              _ ->
                                []
                            end,
                          case Expanded of
                            [] -> [PrefixPath];
                            _ -> Expanded
                          end;
                        false ->
                          [PrefixPath]
                      end;
                    _ ->
                      [PrefixPath]
                  end
              end
          end
      end
  end.

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

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
