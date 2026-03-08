-module(openagentic_tool_read_bytes).

-export([read_bytes_capped/2]).

read_bytes_capped(FullPath, MaxBytes) ->
  Cap = MaxBytes + 1,
  case file:open(FullPath, [read, binary]) of
    {ok, Io} ->
      try
        {ok, Bin} = read_loop(Io, Cap, []),
        _ = file:close(Io),
        Truncated = byte_size(Bin) > MaxBytes,
        Bin2 = case Truncated of true -> binary:part(Bin, 0, MaxBytes); false -> Bin end,
        {ok, Bin2, byte_size(Bin2), Truncated}
      catch
        Class:Reason ->
          _ = file:close(Io),
          {error, {Class, Reason}}
      end;
    Err -> Err
  end.

read_loop(_Io, 0, Acc) ->
  {ok, iolist_to_binary(lists:reverse(Acc))};
read_loop(Io, Left, Acc) ->
  Want = erlang:min(16384, Left),
  case file:read(Io, Want) of
    eof -> {ok, iolist_to_binary(lists:reverse(Acc))};
    {ok, Bin} -> read_loop(Io, Left - byte_size(Bin), [Bin | Acc]);
    {error, Reason} -> {error, Reason}
  end.
