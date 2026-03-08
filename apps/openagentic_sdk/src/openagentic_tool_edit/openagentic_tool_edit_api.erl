-module(openagentic_tool_edit_api).

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_edit_utils:ensure_map(Input0),
  Ctx = openagentic_tool_edit_utils:ensure_map(Ctx0),
  WorkspaceDir = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, undefined)),
  FilePath0 = openagentic_tool_edit_utils:first_value(Input, [<<"file_path">>, file_path, <<"filePath">>, filePath]),
  Old0 = openagentic_tool_edit_utils:first_value(Input, [<<"old">>, old, <<"old_string">>, old_string, <<"oldString">>, oldString]),
  New0 = openagentic_tool_edit_utils:first_value(Input, [<<"new">>, new, <<"new_string">>, new_string, <<"newString">>, newString]),
  ReplaceAll = openagentic_tool_edit_utils:bool_true(
    openagentic_tool_edit_utils:first_value(Input, [<<"replace_all">>, replace_all, <<"replaceAll">>, replaceAll])
  ),
  Count0 = openagentic_tool_edit_utils:int_opt(Input, [<<"count">>, count], undefined),
  Count = case Count0 of undefined -> if ReplaceAll -> 0; true -> 1 end; I -> I end,
  Before = openagentic_tool_edit_utils:string_opt(openagentic_tool_edit_utils:first_value(Input, [<<"before">>, before])),
  After = openagentic_tool_edit_utils:string_opt(openagentic_tool_edit_utils:first_value(Input, [<<"after">>, 'after'])),
  case validate_input(FilePath0, Old0, New0, Count) of
    ok ->
      run_validated(WorkspaceDir, FilePath0, Old0, New0, Count, Before, After);
    {error, Reason} ->
      {error, Reason}
  end.

validate_input(FilePath0, Old0, New0, Count) ->
  FilePathOk = is_binary(FilePath0) orelse is_list(FilePath0),
  OldOk = is_binary(Old0) orelse is_list(Old0),
  NewPresent = New0 =/= undefined,
  NewOk = is_binary(New0) orelse is_list(New0),
  case {FilePathOk, OldOk, NewPresent andalso NewOk} of
    {false, _, _} -> invalid_file_path_error();
    {_, false, _} -> invalid_old_error();
    {_, _, false} -> invalid_new_error();
    _ when not (is_integer(Count) andalso Count >= 0) -> invalid_count_error();
    _ -> ok
  end.

run_validated(WorkspaceDir, FilePath0, Old0, New0, Count, Before, After) ->
  FilePath = string:trim(openagentic_tool_edit_utils:to_bin(FilePath0)),
  Old = openagentic_tool_edit_utils:to_bin(Old0),
  New = openagentic_tool_edit_utils:to_bin(New0),
  case byte_size(FilePath) > 0 of
    false ->
      invalid_file_path_error();
    true ->
      case byte_size(Old) > 0 of
        false ->
          invalid_old_error();
        true ->
          resolve_and_edit(WorkspaceDir, FilePath, Old, New, Count, Before, After)
      end
  end.

resolve_and_edit(undefined, _FilePath, _Old, _New, _Count, _Before, _After) ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: missing workspace_dir in tool context">>}};
resolve_and_edit(WorkspaceDir, FilePath, Old, New, Count, Before, After) ->
  case openagentic_fs:resolve_write_path(WorkspaceDir, FilePath) of
    {error, Reason} ->
      {error, Reason};
    {ok, FullPath0} ->
      FullPath = openagentic_tool_edit_utils:ensure_list(FullPath0),
      case openagentic_tool_edit_utils:is_sensitive_basename(FullPath) of
        true ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: sensitive file name is not allowed">>}};
        false ->
          openagentic_tool_edit_apply:edit_file(FullPath, Old, New, Count, Before, After)
      end
  end.

invalid_file_path_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'file_path' must be a non-empty string">>}}.

invalid_old_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' must be a non-empty string">>}}.

invalid_new_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'new' must be a string">>}}.

invalid_count_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'count' must be a non-negative integer">>}}.
