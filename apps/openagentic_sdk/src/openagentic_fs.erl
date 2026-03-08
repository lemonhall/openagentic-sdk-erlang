-module(openagentic_fs).

-export([
  resolve_project_path/2,
  resolve_tool_path/2,
  resolve_read_path/3,
  resolve_write_path/2,
  is_safe_rel_path/1,
  norm_abs/1,
  norm_abs_bin/1
]).

resolve_project_path(ProjectDir0, RelPath0) -> openagentic_fs_paths:resolve_project_path(ProjectDir0, RelPath0).
resolve_tool_path(ProjectDir0, RawPath0) -> openagentic_fs_paths:resolve_tool_path(ProjectDir0, RawPath0).
resolve_read_path(ProjectDir0, WorkspaceDir0, RawPath0) -> openagentic_fs_paths:resolve_read_path(ProjectDir0, WorkspaceDir0, RawPath0).
resolve_write_path(WorkspaceDir0, RawPath0) -> openagentic_fs_paths:resolve_write_path(WorkspaceDir0, RawPath0).
is_safe_rel_path(Path0) -> openagentic_fs_guards:is_safe_rel_path(Path0).
norm_abs(Path0) -> openagentic_fs_normalize:norm_abs(Path0).
norm_abs_bin(Path0) -> openagentic_fs_normalize:norm_abs_bin(Path0).
