-module(openagentic_tool_list_api).

-include_lib("kernel/include/file.hrl").

-export([run/2]).

-define(DEFAULT_LIMIT, 100).

run(Input0, Ctx0) ->
  Input = openagentic_tool_list_utils:ensure_map(Input0),
  Ctx = openagentic_tool_list_utils:ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  Raw = openagentic_tool_list_utils:first_non_empty(Input, [<<"path">>, path, <<"dir">>, dir, <<"directory">>, directory]),
  case Raw of
    undefined ->
      invalid_path_error();
    _ ->
      case openagentic_fs:resolve_read_path(ProjectDir, WorkspaceDir, Raw) of
        {error, Reason} ->
          {error, Reason};
        {ok, BaseDir0} ->
          handle_base_dir(openagentic_tool_list_utils:ensure_list(BaseDir0))
      end
  end.

handle_base_dir(BaseDir) ->
  case file:read_file_info(BaseDir) of
    {error, _} ->
      Msg = iolist_to_binary([<<"List: not found: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    {ok, Info} when Info#file_info.type =/= directory ->
      Msg = iolist_to_binary([<<"List: not a directory: ">>, openagentic_fs:norm_abs_bin(BaseDir)]),
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    {ok, _Info} ->
      {FilesPlusOne, Truncated} = openagentic_tool_list_scan:collect_files(BaseDir, ?DEFAULT_LIMIT + 1),
      Files0 = case Truncated of true -> lists:sublist(FilesPlusOne, ?DEFAULT_LIMIT); false -> FilesPlusOne end,
      Files = lists:reverse(Files0),
      {ok, #{
        path => openagentic_fs:norm_abs_bin(BaseDir),
        count => length(Files),
        truncated => Truncated,
        output => openagentic_tool_list_render:render_tree(BaseDir, Files)
      }}
  end.

invalid_path_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"List: 'path' must be a non-empty string">>}}.
