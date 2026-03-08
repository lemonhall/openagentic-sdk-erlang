-module(openagentic_tool_glob_api).

-include_lib("kernel/include/file.hrl").

-export([run/2]).

-define(DEFAULT_MAX_MATCHES, 5000).
-define(DEFAULT_MAX_SCANNED_PATHS, 250000).

run(Input0, Ctx0) ->
  Input = openagentic_tool_glob_utils:ensure_map(Input0),
  Ctx = openagentic_tool_glob_utils:ensure_map(Ctx0),
  ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir0 = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  Pattern0 = maps:get(<<"pattern">>, Input, maps:get(pattern, Input, undefined)),
  case valid_pattern(Pattern0) of
    error ->
      invalid_pattern_error();
    {ok, Pattern} ->
      run_with_pattern(Input, ProjectDir0, WorkspaceDir0, Pattern)
  end.

valid_pattern(undefined) ->
  error;
valid_pattern(Pattern0) ->
  Pattern = openagentic_tool_glob_utils:ensure_list(Pattern0),
  case byte_size(string:trim(openagentic_tool_glob_utils:to_bin(Pattern))) > 0 of
    true -> {ok, Pattern};
    false -> error
  end.

run_with_pattern(Input, ProjectDir0, WorkspaceDir0, Pattern) ->
  RootRaw0 = openagentic_tool_glob_utils:first_non_empty(Input, [<<"root">>, root, <<"path">>, path]),
  RootRaw =
    case RootRaw0 of
      undefined -> <<>>;
      _ -> string:trim(openagentic_tool_glob_utils:to_bin(RootRaw0))
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
      handle_base_dir(openagentic_tool_glob_utils:ensure_list(BaseDir0), Pattern)
  end.

handle_base_dir(BaseDir, Pattern) ->
  case file:read_file_info(BaseDir) of
    {ok, Info} when Info#file_info.type =:= directory ->
      EarlyExit = openagentic_tool_glob_pattern:should_early_exit_after_first_match(Pattern),
      Re = openagentic_glob:to_re(Pattern),
      ScanRoots = openagentic_tool_glob_pattern:resolve_scan_roots(BaseDir, Pattern),
      BaseNorm = openagentic_fs:norm_abs_bin(BaseDir),
      case openagentic_tool_glob_scan:scan_roots(
             ScanRoots,
             BaseDir,
             Re,
             ?DEFAULT_MAX_MATCHES,
             ?DEFAULT_MAX_SCANNED_PATHS,
             EarlyExit,
             false
           ) of
        {stop, Matches0, Stop} ->
          openagentic_tool_glob_render:render_stop(BaseDir, Pattern, Matches0, Stop);
        {ok, Matches0} ->
          Matches = lists:sort(Matches0),
          {ok, #{
            root => BaseNorm,
            matches => Matches,
            search_path => BaseNorm,
            pattern => openagentic_tool_glob_utils:to_bin(Pattern),
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
      Msg = iolist_to_binary([
        <<"Glob: cannot access root: ">>,
        openagentic_fs:norm_abs_bin(BaseDir),
        <<" error=">>,
        openagentic_tool_glob_utils:to_bin(E)
      ]),
      {error, {kotlin_error, <<"RuntimeException">>, Msg}}
  end.

invalid_pattern_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Glob: 'pattern' must be a non-empty string">>}}.
