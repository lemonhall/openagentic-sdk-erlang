-module(openagentic_tool_read_file).

-include_lib("kernel/include/file.hrl").

-export([read_file/3]).

-define(MAX_BYTES, 1048576).
-define(MAX_LINE_CHARS, 10000).

read_file(FullPath, OffsetOpt, LimitOpt) ->
  FileSize = file_size_safe(FullPath),
  case openagentic_tool_read_bytes:read_bytes_capped(FullPath, ?MAX_BYTES) of
    {ok, Bin, BytesReturned, BytesTruncated} ->
      case image_mime(FullPath) of
        {ok, Mime} ->
          {ok, #{file_path => openagentic_fs:norm_abs_bin(FullPath), image => base64:encode(Bin), mime_type => openagentic_tool_read_utils:to_bin(Mime), file_size => file_size_out(FileSize, BytesReturned), bytes_returned => BytesReturned, truncated => BytesTruncated}};
        false ->
          text_result(FullPath, FileSize, Bin, BytesReturned, BytesTruncated, OffsetOpt, LimitOpt)
      end;
    {error, Reason} ->
      {error, read_io_error(FullPath, Reason)}
  end.

text_result(FullPath, FileSize, Bin, BytesReturned, BytesTruncated, OffsetOpt, LimitOpt) ->
  Text0 = openagentic_tool_read_lines:decode_text_utf8(Bin),
  EndsWithNewline = openagentic_tool_read_lines:ends_with(Text0, <<"
">>),
  {Lines0, LongLineTruncated} = openagentic_tool_read_lines:split_lines_clamped(Text0, ?MAX_LINE_CHARS),
  Total = length(Lines0),
  Truncated = BytesTruncated orelse LongLineTruncated,
  case (OffsetOpt =/= undefined) orelse (LimitOpt =/= undefined) of
    false -> full_text_result(FullPath, FileSize, Text0, Lines0, EndsWithNewline, BytesReturned, Truncated);
    true -> sliced_text_result(FullPath, FileSize, Lines0, Total, BytesReturned, Truncated, OffsetOpt, LimitOpt)
  end.

full_text_result(FullPath, FileSize, Text0, Lines0, EndsWithNewline, BytesReturned, Truncated) ->
  Content =
    case Truncated of
      true ->
        Joined = iolist_to_binary(lists:join(<<"
">>, Lines0)),
        case EndsWithNewline of true -> <<Joined/binary, "
">>; false -> Joined end;
      false ->
        Text0
    end,
  {ok, #{file_path => openagentic_fs:norm_abs_bin(FullPath), content => Content, file_size => file_size_out(FileSize, BytesReturned), bytes_returned => BytesReturned, truncated => Truncated}}.

sliced_text_result(FullPath, FileSize, Lines0, Total, BytesReturned, Truncated, OffsetOpt, LimitOpt) ->
  Offset1 = case OffsetOpt of undefined -> undefined; OffsetValue -> OffsetValue end,
  Start0 = case Offset1 of undefined -> 0; StartValue -> StartValue - 1 end,
  MaxStart = erlang:max(Total, 1),
  case (Start0 >= 0) andalso (Start0 < MaxStart) of
    false ->
      OffMsg = case Offset1 of undefined -> 1; OffsetValue2 -> OffsetValue2 end,
      Msg = iolist_to_binary([<<"Read: 'offset' out of range: offset=">>, integer_to_binary(OffMsg), <<" total_lines=">>, integer_to_binary(Total)]),
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    true ->
      End0 = case LimitOpt of undefined -> Total; Limit -> erlang:min(Total, Start0 + Limit) end,
      Slice = openagentic_tool_read_lines:slice_list(Lines0, Start0, End0),
      Numbered = openagentic_tool_read_lines:join_numbered(Slice, Start0),
      {ok, #{file_path => openagentic_fs:norm_abs_bin(FullPath), content => Numbered, total_lines => Total, lines_returned => length(Slice), file_size => file_size_out(FileSize, BytesReturned), bytes_returned => BytesReturned, truncated => Truncated}}
  end.

read_io_error(FullPath0, Reason0) ->
  Abs = openagentic_fs:norm_abs_bin(FullPath0),
  Reason = case Reason0 of {error, Inner} -> Inner; Inner -> Inner end,
  case Reason of
    enoent -> {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Read: not found: ">>, Abs])};
    enotdir -> {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Read: not found: ">>, Abs])};
    eacces -> {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read: access denied: ">>, Abs])};
    _ -> {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read failed: ">>, openagentic_tool_read_utils:to_bin(Reason0)])}
  end.

file_size_safe(FullPath) ->
  case file:read_file_info(FullPath) of
    {ok, Info} -> Info#file_info.size;
    _ -> undefined
  end.

file_size_out(undefined, BytesReturned) -> BytesReturned;
file_size_out(Size, _BytesReturned) -> Size.

image_mime(Path0) ->
  Path = openagentic_tool_read_utils:to_bin(Path0),
  Ext = string:lowercase(filename:extension(binary_to_list(Path))),
  case Ext of
    ".png" -> {ok, <<"image/png">>};
    ".jpg" -> {ok, <<"image/jpeg">>};
    ".jpeg" -> {ok, <<"image/jpeg">>};
    ".gif" -> {ok, <<"image/gif">>};
    ".webp" -> {ok, <<"image/webp">>};
    _ -> false
  end.
