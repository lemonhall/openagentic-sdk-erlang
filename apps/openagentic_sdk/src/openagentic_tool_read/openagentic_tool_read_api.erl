-module(openagentic_tool_read_api).

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_read_utils:ensure_map(Input0),
  Ctx = openagentic_tool_read_utils:ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  case openagentic_tool_read_utils:string_field(Input, [<<"file_path">>, file_path, <<"filePath">>, filePath]) of
    {error, Msg} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'file_path' must be a non-empty string">>}};
    {ok, Path0} ->
      case openagentic_fs:resolve_read_path(ProjectDir, WorkspaceDir, Path0) of
        {error, Reason} ->
          {error, Reason};
        {ok, FullPath} ->
          case openagentic_tool_read_utils:is_sensitive_basename(FullPath) of
            true ->
              {error, {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read: access denied: ">>, openagentic_fs:norm_abs_bin(FullPath)])}};
            false ->
              read_with_window(Input, FullPath)
          end
      end
  end.

read_with_window(Input, FullPath) ->
  OffsetRes = openagentic_tool_read_utils:optional_int_field(Input, [<<"offset">>, offset], <<"offset">>),
  LimitRes = openagentic_tool_read_utils:optional_int_field(Input, [<<"limit">>, limit], <<"limit">>),
  case {OffsetRes, LimitRes} of
    {{error, Msg1}, _} -> {error, {kotlin_error, <<"IllegalArgumentException">>, Msg1}};
    {_, {error, Msg2}} -> {error, {kotlin_error, <<"IllegalArgumentException">>, Msg2}};
    {{ok, Offset0}, {ok, Limit0}} ->
      Offset = openagentic_tool_read_lines:normalize_offset_opt(Offset0),
      case (Offset =:= undefined) orelse (Offset >= 1) of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'offset' must be a positive integer (1-based)">>}};
        true ->
          case (Limit0 =:= undefined) orelse (Limit0 >= 0) of
            false -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'limit' must be a non-negative integer">>}};
            true -> openagentic_tool_read_file:read_file(FullPath, Offset, Limit0)
          end
      end
  end.
