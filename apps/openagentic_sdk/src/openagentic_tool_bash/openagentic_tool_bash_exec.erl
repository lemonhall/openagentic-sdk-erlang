-module(openagentic_tool_bash_exec).

-export([run_bash/4]).

run_bash(Command, RunCwd, ProjectDir, TimeoutMs) ->
  case os:find_executable("bash") of
    false ->
      {error, {bash_not_found, <<"bash">>}};
    BashExe0 ->
      BashExe = openagentic_tool_bash_utils:ensure_list(BashExe0),
      Id = openagentic_tool_bash_utils:random_hex(16),
      OutDir = filename:join([ProjectDir, ".openagentic-sdk", "tool-output"]),
      _ = filelib:ensure_dir(filename:join([OutDir, "x"])),
      StderrPath = filename:join([OutDir, "bash." ++ Id ++ ".stderr.txt"]),
      FullPath = filename:join([OutDir, "bash." ++ Id ++ ".txt"]),
      Script = build_script(Command, StderrPath),
      {ok, FullIo} = file:open(FullPath, [write, binary]),
      Port = open_port({spawn_executable, BashExe}, [binary, exit_status, use_stdio, {args, ["-lc", Script]}, {cd, RunCwd}]),
      {StdoutCap, StdoutTotal, ExitCode0, Killed} = openagentic_tool_bash_output:collect_stdout(Port, TimeoutMs, FullIo),
      _ = file:close(FullIo),
      {StderrCap, StderrTotal} = openagentic_tool_bash_output:read_stderr(StderrPath),
      _ = openagentic_tool_bash_output:safe_delete(StderrPath),
      _ = openagentic_tool_bash_output:append_file(FullPath, StderrCap),
      ExitCode = case Killed of true -> 137; false -> ExitCode0 end,
      StdoutTruncated = StdoutTotal > openagentic_tool_bash_output:max_output_bytes(),
      StderrTruncated = StderrTotal > openagentic_tool_bash_output:max_output_bytes(),
      StdoutText = openagentic_tool_bash_paths:normalize_posix_paths_to_windows(openagentic_tool_bash_output:bin_to_utf8(StdoutCap)),
      StderrText = openagentic_tool_bash_paths:normalize_posix_paths_to_windows(openagentic_tool_bash_output:bin_to_utf8(StderrCap)),
      Output0 = openagentic_tool_bash_paths:normalize_posix_paths_to_windows(openagentic_tool_bash_output:bin_to_utf8(<<StdoutCap/binary, StderrCap/binary>>)),
      {Output, OutputLinesTruncated} = openagentic_tool_bash_output:cap_lines(Output0, openagentic_tool_bash_output:max_output_lines()),
      FullOutPathOut = full_output_path(FullPath, StdoutTruncated, StderrTruncated, OutputLinesTruncated),
      {ok, #{
        command => Command,
        exit_code => ExitCode,
        stdout => StdoutText,
        stderr => StderrText,
        stdout_truncated => StdoutTruncated,
        stderr_truncated => StderrTruncated,
        output_lines_truncated => OutputLinesTruncated,
        full_output_file_path => FullOutPathOut,
        output => Output,
        exitCode => ExitCode,
        killed => Killed,
        shellId => null
      }}
  end.

full_output_path(FullPath, StdoutTruncated, StderrTruncated, OutputLinesTruncated) ->
  case StdoutTruncated orelse StderrTruncated orelse OutputLinesTruncated of
    true -> openagentic_fs:norm_abs_bin(FullPath);
    false ->
      _ = openagentic_tool_bash_output:safe_delete(FullPath),
      null
  end.

build_script(Command, StderrRel) ->
  iolist_to_binary(["set -o pipefail; { ", binary_to_list(Command), "; } 2> ", shell_quote(StderrRel)]).

shell_quote(Value0) ->
  Value = openagentic_tool_bash_utils:ensure_list(Value0),
  "'" ++ lists:flatten([case Char of $' -> "'\\''"; _ -> [Char] end || Char <- Value]) ++ "'".
