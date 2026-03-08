-module(openagentic_session_store_tail_repair).

-include_lib("kernel/include/file.hrl").

-export([repair_truncated_tail/1]).

repair_truncated_tail(Path) ->
  case file:read_file_info(Path) of
    {ok, #file_info{size = Size}} when is_integer(Size), Size > 0 ->
      case file:open(Path, [read, binary]) of
        {ok, Io} ->
          Result =
            case file:position(Io, {eof, -1}) of
              {ok, _Pos} -> case file:read(Io, 1) of {ok, <<$\n>>} -> ok; _ -> file:close(Io), truncate_to_last_newline(Path) end;
              _ -> ok
            end,
          _ = file:close(Io),
          Result;
        _ -> ok
      end;
    _ -> ok
  end.

truncate_to_last_newline(Path) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case last_newline_pos(Bin, byte_size(Bin) - 1) of
        -1 -> file:write_file(Path, <<>>);
        Pos -> file:write_file(Path, binary:part(Bin, 0, Pos + 1))
      end;
    _ -> ok
  end.

last_newline_pos(_Bin, Idx) when Idx < 0 -> -1;
last_newline_pos(Bin, Idx) ->
  case binary:at(Bin, Idx) of $\n -> Idx; _ -> last_newline_pos(Bin, Idx - 1) end.
