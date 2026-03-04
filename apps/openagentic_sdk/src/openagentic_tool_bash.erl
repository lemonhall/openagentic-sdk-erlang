-module(openagentic_tool_bash).

-include_lib("kernel/include/file.hrl").

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

-define(DEFAULT_TIMEOUT_MS, 60000).
-define(MAX_OUTPUT_BYTES, 1048576). %% 1 MiB
-define(MAX_OUTPUT_LINES, 2000).

name() -> <<"Bash">>.

description() -> <<"Run a shell command.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),

  Command0 = maps:get(<<"command">>, Input, maps:get(command, Input, undefined)),
  Command = string:trim(to_bin(Command0)),
  case byte_size(Command) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Bash: 'command' must be a non-empty string">>}};
    true ->
      Workdir0 = trim_non_empty(maps:get(<<"workdir">>, Input, maps:get(workdir, Input, undefined))),
      TimeoutMs = timeout_ms(Input),
      case resolve_workdir(ProjectDir, Workdir0) of
        {error, Reason} -> {error, Reason};
        {ok, RunCwd} ->
          run_bash(Command, RunCwd, ProjectDir, TimeoutMs)
      end
  end.

resolve_workdir(ProjectDir, undefined) ->
  case openagentic_fs:resolve_tool_path(ProjectDir, <<".">>) of
    {ok, P} -> {ok, ensure_list(P)};
    Err -> Err
  end;
resolve_workdir(ProjectDir, Workdir) ->
  case openagentic_fs:resolve_tool_path(ProjectDir, Workdir) of
    {error, Reason} ->
      {error, Reason};
    {ok, P0} ->
      P = ensure_list(P0),
      case filelib:is_dir(P) of
        true -> {ok, P};
        false -> {error, {not_a_directory, openagentic_fs:norm_abs_bin(P)}}
      end
  end.

timeout_ms(Input) ->
  case first_int(Input, [<<"timeout">>, timeout, <<"timeout_ms">>, timeout_ms]) of
    undefined ->
      case first_number(Input, [<<"timeout_s">>, timeout_s]) of
        undefined -> ?DEFAULT_TIMEOUT_MS;
        N -> erlang:round(N * 1000)
      end;
    I -> I
  end.

run_bash(Command, RunCwd, ProjectDir, TimeoutMs) ->
  case os:find_executable("bash") of
    false ->
      {error, {bash_not_found, <<"bash">>}};
    BashExe0 ->
      BashExe = ensure_list(BashExe0),
      Id = random_hex(16),
      OutDir = filename:join([ProjectDir, ".openagentic-sdk", "tool-output"]),
      _ = filelib:ensure_dir(filename:join([OutDir, "x"])),
      StderrPath = filename:join([OutDir, "bash." ++ Id ++ ".stderr.txt"]),
      FullPath = filename:join([OutDir, "bash." ++ Id ++ ".txt"]),
      Script = build_script(Command, StderrPath),

      {ok, FullIo} = file:open(FullPath, [write, binary]),
      Port = open_port({spawn_executable, BashExe}, [binary, exit_status, use_stdio, {args, ["-lc", Script]}, {cd, RunCwd}]),
      {StdoutCap, StdoutTotal, ExitCode0, Killed} = collect_stdout(Port, TimeoutMs, FullIo),
      _ = file:close(FullIo),

      {StderrCap, StderrTotal} = read_stderr(StderrPath),
      _ = safe_delete(StderrPath),

      %% Append stderr to full output file (best effort).
      _ = append_file(FullPath, StderrCap),

      ExitCode = case Killed of true -> 137; false -> ExitCode0 end,
      StdoutTruncated = StdoutTotal > ?MAX_OUTPUT_BYTES,
      StderrTruncated = StderrTotal > ?MAX_OUTPUT_BYTES,

      StdoutText = normalize_posix_paths_to_windows(bin_to_utf8(StdoutCap)),
      StderrText = normalize_posix_paths_to_windows(bin_to_utf8(StderrCap)),

      Output0 = normalize_posix_paths_to_windows(bin_to_utf8(<<StdoutCap/binary, StderrCap/binary>>)),
      {Output, OutputLinesTruncated} = cap_lines(Output0, ?MAX_OUTPUT_LINES),

      Keep = StdoutTruncated orelse StderrTruncated orelse OutputLinesTruncated,
      FullOutPathOut =
        case Keep of
          true -> openagentic_fs:norm_abs_bin(FullPath);
          false ->
            _ = safe_delete(FullPath),
            null
        end,

      {ok, #{
        command => Command,
        exit_code => ExitCode,
        stdout => StdoutText,
        stderr => StderrText,
        stdout_truncated => StdoutTruncated,
        stderr_truncated => StderrTruncated,
        output_lines_truncated => OutputLinesTruncated,
        full_output_file_path => FullOutPathOut,
        %% CAS-compatible aliases:
        output => Output,
        exitCode => ExitCode,
        killed => Killed,
        shellId => null
      }}
  end.

build_script(Command, StderrRel) ->
  %% Redirect stderr for the entire command group.
  %% Note: We pass an absolute Windows path (quoted) to bash.
  iolist_to_binary([
    "set -o pipefail; { ",
    binary_to_list(Command),
    "; } 2> ",
    shell_quote(StderrRel)
  ]).

shell_quote(S0) ->
  %% Minimal single-quote escaping for bash.
  S = ensure_list(S0),
  "'" ++ lists:flatten([case C of $' -> "'\\''"; _ -> [C] end || C <- S]) ++ "'".

collect_stdout(Port, TimeoutMs, FullIo) ->
  Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
  collect_loop(Port, Deadline, FullIo, <<>>, 0, undefined, false).

collect_loop(Port, Deadline, FullIo, Cap0, Total0, Exit0, Killed0) ->
  Now = erlang:monotonic_time(millisecond),
  Remaining = erlang:max(0, Deadline - Now),
  receive
    {Port, {data, Bin}} when is_binary(Bin) ->
      _ = file:write(FullIo, Bin),
      Total1 = Total0 + byte_size(Bin),
      Cap1 =
        case byte_size(Cap0) < (?MAX_OUTPUT_BYTES + 1) of
          true ->
            Want = erlang:min(byte_size(Bin), (?MAX_OUTPUT_BYTES + 1) - byte_size(Cap0)),
            iolist_to_binary([Cap0, binary:part(Bin, 0, Want)]);
          false ->
            Cap0
        end,
      collect_loop(Port, Deadline, FullIo, Cap1, Total1, Exit0, Killed0);
    {Port, {exit_status, Code}} ->
      Cap2 = cap_bytes(Cap0, ?MAX_OUTPUT_BYTES),
      {Cap2, Total0, Code, Killed0};
    {'EXIT', Port, _} ->
      Cap2 = cap_bytes(Cap0, ?MAX_OUTPUT_BYTES),
      {Cap2, Total0, Exit0, Killed0}
  after Remaining ->
    %% timeout
    _ = catch erlang:port_close(Port),
    Cap2 = cap_bytes(Cap0, ?MAX_OUTPUT_BYTES),
    {Cap2, Total0, 137, true}
  end.

read_stderr(Path) ->
  case file:read_file_info(Path) of
    {ok, Info} ->
      Sz = Info#file_info.size,
      Total = if is_integer(Sz) -> Sz; true -> 0 end,
      case file:read_file(Path) of
        {ok, Bin} ->
          {cap_bytes(Bin, ?MAX_OUTPUT_BYTES), Total};
        _ ->
          {<<>>, Total}
      end;
    _ ->
      {<<>>, 0}
  end.

append_file(Path, Bin) ->
  case Bin of
    <<>> -> ok;
    _ ->
      case file:open(Path, [append, binary]) of
        {ok, Io} ->
          _ = file:write(Io, Bin),
          file:close(Io);
        _ -> ok
      end
  end.

safe_delete(Path) ->
  _ = file:delete(Path),
  ok.

cap_bytes(Bin, Max) when is_binary(Bin) ->
  case byte_size(Bin) > Max of
    true -> binary:part(Bin, 0, Max);
    false -> Bin
  end.

cap_lines(Text0, MaxLines) ->
  Text = to_bin(Text0),
  Lines = binary:split(Text, <<"\n">>, [global]),
  case length(Lines) > MaxLines of
    false -> {Text, false};
    true ->
      Kept = lists:sublist(Lines, MaxLines),
      {iolist_to_binary(lists:join(<<"\n">>, Kept)), true}
  end.

bin_to_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end.

normalize_posix_paths_to_windows(Text0) ->
  Text = to_bin(Text0),
  Os0 = os:type(),
  case Os0 of
    {win32, _} ->
      T1 = replace_wsl_paths(Text),
      replace_msys_paths(T1);
    _ ->
      Text
  end.

replace_wsl_paths(Bin) ->
  replace_paths(Bin, wsl, 0, []).

replace_msys_paths(Bin) ->
  replace_paths(Bin, msys, 0, []).

replace_paths(Bin, Type, Pos0, Acc0) ->
  case find_path(Bin, Type, Pos0) of
    none ->
      Tail = binary:part(Bin, Pos0, byte_size(Bin) - Pos0),
      iolist_to_binary(lists:reverse([Tail | Acc0]));
    {Start, End, Repl} ->
      Prefix = binary:part(Bin, Pos0, Start - Pos0),
      replace_paths(Bin, Type, End, [Repl, Prefix | Acc0])
  end.

find_path(Bin, wsl, Pos0) ->
  Size = byte_size(Bin),
  case binary:match(Bin, <<"/mnt/">>, [{scope, {Pos0, Size - Pos0}}]) of
    nomatch ->
      none;
    {P, _} ->
      case path_prefix_ok(Bin, P) andalso (P + 6 < Size) of
        false ->
          find_path(Bin, wsl, P + 1);
        true ->
          Drive = binary:at(Bin, P + 5),
          Slash = binary:at(Bin, P + 6),
          case is_alpha(Drive) andalso Slash =:= $/ of
            false ->
              find_path(Bin, wsl, P + 1);
            true ->
              RestStart = P + 7,
              End = scan_path_end(Bin, RestStart),
              Rest = binary:part(Bin, RestStart, End - RestStart),
              Repl = win_path(Drive, Rest),
              {P, End, Repl}
          end
      end
  end;
find_path(Bin, msys, Pos0) ->
  Size = byte_size(Bin),
  case binary:match(Bin, <<"/">>, [{scope, {Pos0, Size - Pos0}}]) of
    nomatch ->
      none;
    {P, _} ->
      case path_prefix_ok(Bin, P) andalso (P + 2 < Size) of
        false ->
          find_path(Bin, msys, P + 1);
        true ->
          A = binary:at(Bin, P + 1),
          B = binary:at(Bin, P + 2),
          case is_alpha(A) andalso B =:= $/ of
            false ->
              find_path(Bin, msys, P + 1);
            true ->
              %% Skip /mnt/<d>/ form (handled by WSL pass).
              case binary:part(Bin, P, erlang:min(5, Size - P)) of
                <<"/mnt/">> ->
                  find_path(Bin, msys, P + 1);
                _ ->
                  RestStart = P + 3,
                  End = scan_path_end(Bin, RestStart),
                  Rest = binary:part(Bin, RestStart, End - RestStart),
                  Repl = win_path(A, Rest),
                  {P, End, Repl}
              end
          end
      end
  end.

path_prefix_ok(_Bin, 0) -> true;
path_prefix_ok(Bin, P) when P > 0 ->
  Prev = binary:at(Bin, P - 1),
  lists:member(Prev, [$\s, $\t, $\r, $\n, $', $\", $(]).

scan_path_end(Bin, I) ->
  Size = byte_size(Bin),
  scan_path_end2(Bin, I, Size).

scan_path_end2(_Bin, I, Size) when I >= Size -> Size;
scan_path_end2(Bin, I, Size) ->
  C = binary:at(Bin, I),
  case lists:member(C, [$\s, $\t, $\r, $\n, $', $\", $(, $)]) of
    true -> I;
    false -> scan_path_end2(Bin, I + 1, Size)
  end.

is_alpha(C) when C >= $a, C =< $z -> true;
is_alpha(C) when C >= $A, C =< $Z -> true;
is_alpha(_) -> false.

win_path(DriveChar, Rest0) ->
  Drive = string:uppercase(<<DriveChar>>),
  Rest = binary:replace(Rest0, <<"/">>, <<"\\">>, [global]),
  <<Drive/binary, ":\\", Rest/binary>>.

trim_non_empty(undefined) -> undefined;
trim_non_empty(V0) ->
  V = to_bin(V0),
  case byte_size(string:trim(V)) > 0 of
    true -> V;
    false -> undefined
  end.

first_int(Map, Keys) ->
  lists:foldl(
    fun (K, Acc) ->
      case Acc of
        undefined -> to_int(maps:get(K, Map, undefined));
        _ -> Acc
      end
    end,
    undefined,
    Keys
  ).

to_int(undefined) -> undefined;
to_int(I) when is_integer(I) -> I;
to_int(B) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of X when is_integer(X) -> X; _ -> undefined end;
to_int(L) when is_list(L) ->
  case (catch list_to_integer(string:trim(L))) of X when is_integer(X) -> X; _ -> undefined end;
to_int(_) -> undefined.

first_number(Map, Keys) ->
  lists:foldl(
    fun (K, Acc) ->
      case Acc of
        undefined -> to_number(maps:get(K, Map, undefined));
        _ -> Acc
      end
    end,
    undefined,
    Keys
  ).

to_number(undefined) -> undefined;
to_number(I) when is_integer(I) -> I * 1.0;
to_number(F) when is_float(F) -> F;
to_number(B) when is_binary(B) ->
  case (catch list_to_float(binary_to_list(string:trim(B)))) of
    X when is_float(X) -> X;
    _ ->
      case (catch binary_to_integer(string:trim(B))) of
        Y when is_integer(Y) -> Y * 1.0;
        _ -> undefined
      end
  end;
to_number(L) when is_list(L) ->
  case (catch list_to_float(string:trim(L))) of
    X when is_float(X) -> X;
    _ ->
      case (catch list_to_integer(string:trim(L))) of
        Y when is_integer(Y) -> Y * 1.0;
        _ -> undefined
      end
  end;
to_number(_) -> undefined.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
