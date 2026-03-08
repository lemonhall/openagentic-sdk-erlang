-module(openagentic_fs_paths).

-export([resolve_project_path/2, resolve_read_path/3, resolve_tool_path/2, resolve_write_path/2]).

resolve_read_path(ProjectDir0, WorkspaceDir0, RawPath0) ->
  ProjectDir = openagentic_fs_utils:ensure_list(ProjectDir0),
  WorkspaceDir = openagentic_fs_utils:ensure_list(WorkspaceDir0),
  RawPath = openagentic_fs_utils:ensure_list(RawPath0),
  {Scope, Path} = parse_scope_prefix(RawPath),
  case Scope of
    workspace -> resolve_tool_path(WorkspaceDir, Path);
    project -> resolve_tool_path(ProjectDir, Path);
    auto ->
      case (WorkspaceDir =/= []) andalso (openagentic_fs_guards:has_drive_prefix(Path) orelse openagentic_fs_guards:is_abs(Path)) of
        true ->
          case resolve_tool_path(WorkspaceDir, Path) of
            {ok, _} = Ok -> Ok;
            _ -> resolve_tool_path(ProjectDir, Path)
          end;
        false ->
          resolve_tool_path(ProjectDir, Path)
      end
  end.

resolve_write_path(WorkspaceDir0, RawPath0) ->
  WorkspaceDir = openagentic_fs_utils:ensure_list(WorkspaceDir0),
  RawPath = openagentic_fs_utils:ensure_list(RawPath0),
  {Scope, Path} = parse_scope_prefix(RawPath),
  case Scope of
    project ->
      RootShown = openagentic_fs_normalize:norm_abs_bin(WorkspaceDir),
      {error, {kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"Write path must be under workspace root: ">>, RootShown])}};
    _ ->
      resolve_tool_path(WorkspaceDir, Path)
  end.

parse_scope_prefix(Path0) ->
  Path = string:trim(openagentic_fs_utils:ensure_list(Path0)),
  Lower = string:lowercase(Path),
  case lists:prefix("workspace:", Lower) of
    true -> {workspace, string:trim(lists:nthtail(length("workspace:"), Path))};
    false ->
      case lists:prefix("ws:", Lower) of
        true -> {workspace, string:trim(lists:nthtail(length("ws:"), Path))};
        false ->
          case lists:prefix("project:", Lower) of
            true -> {project, string:trim(lists:nthtail(length("project:"), Path))};
            false ->
              case lists:prefix("proj:", Lower) of
                true -> {project, string:trim(lists:nthtail(length("proj:"), Path))};
                false -> {auto, Path}
              end
          end
      end
  end.

resolve_project_path(ProjectDir0, RelPath0) ->
  ProjectDir = openagentic_fs_utils:ensure_list(ProjectDir0),
  RelPath = openagentic_fs_utils:ensure_list(RelPath0),
  case openagentic_fs_guards:is_safe_rel_path(RelPath) of
    false -> {error, unsafe_path};
    true -> {ok, filename:join([ProjectDir, RelPath])}
  end.

resolve_tool_path(ProjectDir0, RawPath0) ->
  ProjectDir = openagentic_fs_utils:ensure_list(ProjectDir0),
  RawPath = openagentic_fs_utils:ensure_list(RawPath0),
  Stripped = string:trim(RawPath),
  case Stripped of
    "" ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"tool path must be non-empty">>}};
    _ ->
      FullPath =
        case openagentic_fs_guards:has_drive_prefix(Stripped) orelse openagentic_fs_guards:is_abs(Stripped) of
          true -> openagentic_fs_normalize:abs_norm(Stripped);
          false -> openagentic_fs_normalize:abs_norm(filename:join([ProjectDir, Stripped]))
        end,
      openagentic_fs_symlink:check_under_root(ProjectDir, filename:nativename(FullPath))
  end.
