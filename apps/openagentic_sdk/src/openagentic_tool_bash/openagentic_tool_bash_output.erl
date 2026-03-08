-module(openagentic_tool_bash_output).

-include_lib("kernel/include/file.hrl").

-export([append_file/2, bin_to_utf8/1, cap_lines/2, collect_stdout/3, max_output_bytes/0, max_output_lines/0, read_stderr/1, safe_delete/1]).

-define(MAX_OUTPUT_BYTES, 1048576).
-define(MAX_OUTPUT_LINES, 2000).

max_output_bytes() -> ?MAX_OUTPUT_BYTES.
max_output_lines() -> ?MAX_OUTPUT_LINES.

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
      {cap_bytes(Cap0, ?MAX_OUTPUT_BYTES), Total0, Code, Killed0};
    {'EXIT', Port, _} ->
      {cap_bytes(Cap0, ?MAX_OUTPUT_BYTES), Total0, Exit0, Killed0}
  after Remaining ->
    _ = catch erlang:port_close(Port),
    {cap_bytes(Cap0, ?MAX_OUTPUT_BYTES), Total0, 137, true}
  end.

read_stderr(Path) ->
  case file:read_file_info(Path) of
    {ok, Info} ->
      Size = Info#file_info.size,
      Total = if is_integer(Size) -> Size; true -> 0 end,
      case file:read_file(Path) of
        {ok, Bin} -> {cap_bytes(Bin, ?MAX_OUTPUT_BYTES), Total};
        _ -> {<<>>, Total}
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
  Text = openagentic_tool_bash_utils:to_bin(Text0),
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
