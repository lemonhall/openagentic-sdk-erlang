-module(openagentic_tool_bash_api).

-include_lib("kernel/include/file.hrl").

-export([run/2]).

-define(DEFAULT_TIMEOUT_MS, 60000).

run(Input0, Ctx0) ->
  Input = openagentic_tool_bash_utils:ensure_map(Input0),
  Ctx = openagentic_tool_bash_utils:ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  Command0 = maps:get(<<"command">>, Input, maps:get(command, Input, undefined)),
  Command = string:trim(openagentic_tool_bash_utils:to_bin(Command0)),
  case byte_size(Command) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Bash: 'command' must be a non-empty string">>}};
    true ->
      Workdir0 = openagentic_tool_bash_utils:trim_non_empty(maps:get(<<"workdir">>, Input, maps:get(workdir, Input, undefined))),
      TimeoutMs = timeout_ms(Input),
      case resolve_workdir(ProjectDir, Workdir0) of
        {error, Reason} -> {error, Reason};
        {ok, RunCwd} -> openagentic_tool_bash_exec:run_bash(Command, RunCwd, ProjectDir, TimeoutMs)
      end
  end.

resolve_workdir(ProjectDir, undefined) ->
  case openagentic_fs:resolve_tool_path(ProjectDir, <<".">>) of
    {ok, Path} -> {ok, openagentic_tool_bash_utils:ensure_list(Path)};
    Err -> Err
  end;
resolve_workdir(ProjectDir, Workdir) ->
  case openagentic_fs:resolve_tool_path(ProjectDir, Workdir) of
    {error, Reason} ->
      {error, Reason};
    {ok, Path0} ->
      Path = openagentic_tool_bash_utils:ensure_list(Path0),
      case file:read_file_info(Path) of
        {ok, Info} when Info#file_info.type =:= directory -> {ok, Path};
        {ok, _Info} ->
          Msg = iolist_to_binary([<<"Bash: not a directory: ">>, openagentic_fs:norm_abs_bin(Path)]),
          {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
        {error, enoent} ->
          Msg = iolist_to_binary([<<"Bash: not found: ">>, openagentic_fs:norm_abs_bin(Path)]),
          {error, {kotlin_error, <<"FileNotFoundException">>, Msg}};
        {error, Err} ->
          Msg = iolist_to_binary([<<"Bash: cannot access workdir: ">>, openagentic_fs:norm_abs_bin(Path), <<" error=">>, openagentic_tool_bash_utils:to_bin(Err)]),
          {error, {kotlin_error, <<"RuntimeException">>, Msg}}
      end
  end.

timeout_ms(Input) ->
  case openagentic_tool_bash_utils:first_int(Input, [<<"timeout">>, timeout, <<"timeout_ms">>, timeout_ms]) of
    undefined ->
      case openagentic_tool_bash_utils:first_number(Input, [<<"timeout_s">>, timeout_s]) of
        undefined -> ?DEFAULT_TIMEOUT_MS;
        Number -> erlang:round(Number * 1000)
      end;
    Int -> Int
  end.
