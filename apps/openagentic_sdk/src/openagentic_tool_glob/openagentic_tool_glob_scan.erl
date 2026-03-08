-module(openagentic_tool_glob_scan).

-export([scan_roots/7]).

scan_roots(ScanRoots, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst) ->
  scan_roots(ScanRoots, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, 0, []).

scan_roots([], _BaseDir, _Re, _MaxMatches, _MaxScanned, _EarlyExit, _WorkspaceFirst, _Scanned, Acc) ->
  {ok, Acc};
scan_roots([Root0 | Rest], BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, Scanned0, Acc0) ->
  Root = openagentic_tool_glob_utils:ensure_list(Root0),
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
      walk_child(Name0, Dir, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, AccIn)
    end,
    {ok, Scanned0, Acc0},
    Children
  ).

walk_child(_Name0, _Dir, _BaseDir, _Re, _MaxMatches, _MaxScanned, _EarlyExit, _WorkspaceFirst, _SearchRoot, {stop, _Acc, _Stop} = AccIn) ->
  AccIn;
walk_child(Name0, Dir, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, {ok, Scanned1, Acc1}) ->
  Name = openagentic_tool_glob_utils:ensure_list(Name0),
  Full = filename:join([Dir, Name]),
  Scanned2 = Scanned1 + 1,
  case Scanned2 >= MaxScanned of
    true ->
      {stop, Acc1, {max_scanned_paths, BaseDir}};
    false ->
      handle_path(Full, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1)
  end.

handle_path(Full, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1) ->
  case filelib:is_dir(Full) of
    true ->
      walk_dir(Full, BaseDir, Re, MaxMatches, MaxScanned, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1);
    false ->
      maybe_add_match(Full, BaseDir, Re, MaxMatches, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1)
  end.

maybe_add_match(Full, BaseDir, Re, MaxMatches, EarlyExit, WorkspaceFirst, SearchRoot, Scanned2, Acc1) ->
  RelPath = openagentic_glob:relpath(BaseDir, Full),
  case re:run(RelPath, Re, [{capture, none}]) of
    nomatch ->
      {ok, Scanned2, Acc1};
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
      end
  end.
