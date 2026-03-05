-module(openagentic_tool_read).

-include_lib("kernel/include/file.hrl").

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Read">>.

description() -> <<"Read a text file. Supports line-based offset/limit.">>.

-define(MAX_BYTES, 1048576). %% 1 MiB
-define(MAX_LINE_CHARS, 10000).

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  case string_field(Input, [<<"file_path">>, file_path, <<"filePath">>, filePath]) of
    {error, Msg} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'file_path' must be a non-empty string">>}};
    {ok, Path0} ->
      case openagentic_fs:resolve_read_path(ProjectDir, WorkspaceDir, Path0) of
        {error, Reason} ->
          {error, Reason};
        {ok, FullPath} ->
          case is_sensitive_basename(FullPath) of
            true ->
              {error, {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read: access denied: ">>, openagentic_fs:norm_abs_bin(FullPath)])}};
            false ->
          case {optional_int_field(Input, [<<"offset">>, offset], <<"offset">>), optional_int_field(Input, [<<"limit">>, limit], <<"limit">>)} of
            {{error, Msg1}, _} ->
              {error, {kotlin_error, <<"IllegalArgumentException">>, Msg1}};
            {_, {error, Msg2}} ->
              {error, {kotlin_error, <<"IllegalArgumentException">>, Msg2}};
            {{ok, Offset0}, {ok, Limit0}} ->
              Offset = normalize_offset_opt(Offset0),
              case (Offset =:= undefined) orelse (Offset >= 1) of
                false ->
                  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'offset' must be a positive integer (1-based)">>}};
                true ->
                  case (Limit0 =:= undefined) orelse (Limit0 >= 0) of
                    false ->
                      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Read: 'limit' must be a non-negative integer">>}};
                    true ->
                      read_file(FullPath, Offset, Limit0)
                  end
              end
          end
          end
      end
  end.

read_file(FullPath, OffsetOpt, LimitOpt) ->
  FileSize = file_size_safe(FullPath),
  case read_bytes_capped(FullPath, ?MAX_BYTES) of
    {ok, Bin, BytesReturned, BytesTruncated} ->
      case image_mime(FullPath) of
        {ok, Mime} ->
          {ok, #{
            file_path => openagentic_fs:norm_abs_bin(FullPath),
            image => base64:encode(Bin),
            mime_type => to_bin(Mime),
            file_size => file_size_out(FileSize, BytesReturned),
            bytes_returned => BytesReturned,
            truncated => BytesTruncated
          }};
        false ->
          Text0 = decode_text_utf8(Bin),
          EndsWithNewline = ends_with(Text0, <<"\n">>),
          {Lines0, LongLineTruncated} = split_lines_clamped(Text0, ?MAX_LINE_CHARS),
          Total = length(Lines0),
          Truncated = BytesTruncated orelse LongLineTruncated,
          case (OffsetOpt =/= undefined) orelse (LimitOpt =/= undefined) of
            false ->
              Content =
                case Truncated of
                  true ->
                    Joined = iolist_to_binary(lists:join(<<"\n">>, Lines0)),
                    case EndsWithNewline of
                      true -> <<Joined/binary, "\n">>;
                      false -> Joined
                    end;
                  false ->
                    Text0
                end,
              {ok, #{
                file_path => openagentic_fs:norm_abs_bin(FullPath),
                content => Content,
                file_size => file_size_out(FileSize, BytesReturned),
                bytes_returned => BytesReturned,
                truncated => Truncated
              }};
            true ->
              Offset1 = case OffsetOpt of undefined -> undefined; V0 -> V0 end,
              Start0 = case Offset1 of undefined -> 0; V1 -> V1 - 1 end,
              MaxStart = erlang:max(Total, 1),
              case (Start0 >= 0) andalso (Start0 < MaxStart) of
                false ->
                  OffMsg = case Offset1 of undefined -> 1; V2 -> V2 end,
                  Msg =
                    iolist_to_binary([
                      <<"Read: 'offset' out of range: offset=">>,
                      integer_to_binary(OffMsg),
                      <<" total_lines=">>,
                      integer_to_binary(Total)
                    ]),
                  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
                true ->
                  End0 =
                    case LimitOpt of
                      undefined -> Total;
                      L -> erlang:min(Total, Start0 + L)
                    end,
                  Slice = slice_list(Lines0, Start0, End0),
                  Numbered = join_numbered(Slice, Start0),
                  {ok, #{
                    file_path => openagentic_fs:norm_abs_bin(FullPath),
                    content => Numbered,
                    total_lines => Total,
                    lines_returned => length(Slice),
                    file_size => file_size_out(FileSize, BytesReturned),
                    bytes_returned => BytesReturned,
                    truncated => Truncated
                  }}
              end
          end
      end;
    {error, Reason} ->
      {error, read_io_error(FullPath, Reason)}
  end.

read_io_error(FullPath0, Reason0) ->
  FullPath = FullPath0,
  Abs = openagentic_fs:norm_abs_bin(FullPath),
  Reason =
    case Reason0 of
      {error, R} -> R;
      R -> R
    end,
  case Reason of
    enoent ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Read: not found: ">>, Abs])};
    enotdir ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Read: not found: ">>, Abs])};
    eacces ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read: access denied: ">>, Abs])};
    _ ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Read failed: ">>, to_bin(Reason0)])}
  end.

normalize_offset_opt(undefined) -> undefined;
normalize_offset_opt(I) when is_integer(I), I =:= 0 -> 1;
normalize_offset_opt(I) when is_integer(I) -> I;
normalize_offset_opt(_) -> undefined.

join_numbered(Lines, Start0) ->
  Start = erlang:max(0, Start0),
  case Lines of
    [] ->
      <<>>;
    _ ->
      Idxs = lists:seq(0, length(Lines) - 1),
      iolist_to_binary(
        lists:join(
          <<"\n">>,
          [iolist_to_binary([integer_to_list(Start + I + 1), <<": ">>, L]) || {I, L} <- lists:zip(Idxs, Lines)]
        )
      )
  end.

split_lines_clamped(TextBin, MaxLineChars) when is_binary(TextBin) ->
  %% Normalize CRLF by trimming trailing \r per line.
  Raw = binary:split(TextBin, <<"\n">>, [global]),
  Lines1 = [strip_cr(L) || L <- Raw],
  %% If the content ends with "\n", drop exactly one trailing empty line.
  Lines2 =
    case ends_with(TextBin, <<"\n">>) of
      true ->
        case Lines1 of
          [] -> [];
          _ ->
            case lists:last(Lines1) of
              <<>> -> lists:sublist(Lines1, length(Lines1) - 1);
              _ -> Lines1
            end
        end;
      false ->
        Lines1
    end,
  clamp_lines(Lines2, MaxLineChars).

clamp_lines(Lines, Max) ->
  lists:foldr(
    fun (L, {Acc, Trunc}) ->
      case string:length(L) =< Max of
        true -> {[L | Acc], Trunc};
        false ->
          Prefix = string:slice(L, 0, Max),
          {[<<Prefix/binary, "…(truncated)">> | Acc], true}
      end
    end,
    {[], false},
    Lines
  ).

strip_cr(L) ->
  Sz = byte_size(L),
  case Sz of
    0 -> <<>>;
    _ ->
      RestSz = Sz - 1,
      case L of
        <<Rest:RestSz/binary, $\r>> -> Rest;
        _ -> L
      end
  end.

drop(L, 0) -> L;
drop([], _N) -> [];
drop([_ | T], N) when N > 0 -> drop(T, N - 1).

take(_L, 0) -> [];
take([], _N) -> [];
take([H | T], N) when N > 0 -> [H | take(T, N - 1)].

optional_int_field(Map, Keys, FieldName) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined ->
      {ok, undefined};
    I when is_integer(I) ->
      {ok, I};
    B when is_binary(B) ->
      Str = string:trim(B),
      case byte_size(Str) of
        0 -> {ok, undefined};
        _ ->
          case (catch binary_to_integer(Str)) of
            X when is_integer(X) -> {ok, X};
            _ -> {error, iolist_to_binary([<<"Read: '">>, FieldName, <<"' must be an integer">>])}
          end
      end;
    L when is_list(L) ->
      B = unicode:characters_to_binary(L, utf8),
      optional_int_field(#{x => B}, [x], FieldName);
    _ ->
      {error, iolist_to_binary([<<"Read: '">>, FieldName, <<"' must be an integer">>])}
  end.

string_field(Map, Keys) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined ->
      undefined;
    B when is_binary(B) ->
      S = string:trim(B),
      case byte_size(S) > 0 of true -> {ok, S}; false -> undefined end;
    L when is_list(L) ->
      string_field(#{x => unicode:characters_to_binary(L, utf8)}, [x]);
    _ ->
      {error, <<"Read: 'file_path' must be a non-empty string">>}
  end.

decode_text_utf8(Bin) when is_binary(Bin) ->
  try
    unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ ->
      unicode:characters_to_binary(Bin, latin1)
  end.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.

slice_list(L, Start0, End0) ->
  Start = erlang:max(0, Start0),
  End = erlang:max(Start, End0),
  take(drop(L, Start), End - Start).

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
        C:R ->
          _ = file:close(Io),
          {error, {C, R}}
      end;
    Err ->
      Err
  end.

read_loop(_Io, 0, Acc) ->
  {ok, iolist_to_binary(lists:reverse(Acc))};
read_loop(Io, Left, Acc) ->
  Want = erlang:min(16384, Left),
  case file:read(Io, Want) of
    eof ->
      {ok, iolist_to_binary(lists:reverse(Acc))};
    {ok, Bin} ->
      read_loop(Io, Left - byte_size(Bin), [Bin | Acc]);
    {error, Reason} ->
      {error, Reason}
  end.

file_size_safe(FullPath) ->
  case file:read_file_info(FullPath) of
    {ok, Info} -> Info#file_info.size;
    _ -> undefined
  end.

file_size_out(undefined, BytesReturned) -> BytesReturned;
file_size_out(Sz, _BytesReturned) -> Sz.

image_mime(Path0) ->
  Path = to_bin(Path0),
  Ext0 = filename:extension(binary_to_list(Path)),
  Ext = string:lowercase(Ext0),
  case Ext of
    ".png" -> {ok, <<"image/png">>};
    ".jpg" -> {ok, <<"image/jpeg">>};
    ".jpeg" -> {ok, <<"image/jpeg">>};
    ".gif" -> {ok, <<"image/gif">>};
    ".webp" -> {ok, <<"image/webp">>};
    _ -> false
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

is_sensitive_basename(Path0) ->
  Path = to_bin(Path0),
  Base = string:lowercase(to_bin(filename:basename(binary_to_list(Path)))),
  case Base of
    <<".env">> -> true;
    <<"id_rsa">> -> true;
    <<"id_ed25519">> -> true;
    _ ->
      case Base of
        <<".env.", _/binary>> ->
          Base =/= <<".env.example">>;
        _ ->
          Ext0 = filename:extension(binary_to_list(Base)),
          Ext = string:lowercase(Ext0),
          lists:member(Ext, [".pem", ".key", ".p12", ".pfx"])
      end
  end.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
