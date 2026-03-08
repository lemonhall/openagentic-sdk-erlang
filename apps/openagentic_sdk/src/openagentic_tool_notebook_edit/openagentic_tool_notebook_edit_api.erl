-module(openagentic_tool_notebook_edit_api).

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_notebook_edit_utils:ensure_map(Input0),
  Ctx = openagentic_tool_notebook_edit_utils:ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  NotebookPath0 = maps:get(<<"notebook_path">>, Input, maps:get(notebook_path, Input, undefined)),
  case NotebookPath0 of
    undefined ->
      invalid_notebook_path_error();
    _ ->
      NotebookPath = openagentic_tool_notebook_edit_utils:to_bin(NotebookPath0),
      case byte_size(string:trim(NotebookPath)) > 0 of
        false -> invalid_notebook_path_error();
        true -> resolve_notebook(ProjectDir, NotebookPath, Input)
      end
  end.

resolve_notebook(ProjectDir, NotebookPath, Input) ->
  case openagentic_fs:resolve_tool_path(ProjectDir, NotebookPath) of
    {error, Reason} ->
      {error, Reason};
    {ok, FullPath0} ->
      FullPath = openagentic_tool_notebook_edit_utils:ensure_list(FullPath0),
      case filelib:is_regular(FullPath) of
        false ->
          Msg = iolist_to_binary([<<"NotebookEdit: not found: ">>, openagentic_fs:norm_abs_bin(FullPath)]),
          {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
        true ->
          openagentic_tool_notebook_edit_ops:edit_notebook(FullPath, Input)
      end
  end.

invalid_notebook_path_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"NotebookEdit: 'notebook_path' must be a non-empty string">>}}.
