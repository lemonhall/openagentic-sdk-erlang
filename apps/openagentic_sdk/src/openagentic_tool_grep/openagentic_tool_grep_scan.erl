-module(openagentic_tool_grep_scan).

-export([file_contains_match/2, scan_one_file/5]).

-define(MAX_MATCHES, 5000).

scan_one_file(Path, QueryRe, BeforeN, AfterN, Acc0) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case safe_utf8_lines(Bin) of
        {ok, Lines} ->
          AbsPath = openagentic_fs:norm_abs_bin(Path),
          scan_lines(Lines, 1, [], AbsPath, QueryRe, BeforeN, AfterN, Acc0);
        {error, _} ->
          {ok, Acc0}
      end;
    _ ->
      {ok, Acc0}
  end.

scan_lines([], _LineNo, _PrevRev, _AbsPath, _QueryRe, _BeforeN, _AfterN, Acc) ->
  {ok, Acc};
scan_lines([Line0 | Rest], LineNo, PrevRev, AbsPath, QueryRe, BeforeN, AfterN, Acc0) ->
  case length(Acc0) >= ?MAX_MATCHES of
    true -> {truncated, Acc0};
    false ->
      Line = trim_cr(Line0),
      case re:run(Line, QueryRe, [{capture, none}]) of
        match ->
          Match = #{
            file_path => AbsPath,
            line => LineNo,
            text => openagentic_tool_grep_utils:to_bin(Line),
            before_context => before_context(BeforeN, PrevRev),
            after_context => after_context(AfterN, Rest)
          },
          scan_lines(Rest, LineNo + 1, [Line | PrevRev], AbsPath, QueryRe, BeforeN, AfterN, [Match | Acc0]);
        nomatch ->
          scan_lines(Rest, LineNo + 1, [Line | PrevRev], AbsPath, QueryRe, BeforeN, AfterN, Acc0)
      end
  end.

before_context(BeforeN, PrevRev) when BeforeN > 0 ->
  TakeN = erlang:min(BeforeN, length(PrevRev)),
  Slice = lists:reverse(lists:sublist(PrevRev, TakeN)),
  [openagentic_tool_grep_utils:to_bin(Line) || Line <- Slice];
before_context(_BeforeN, _PrevRev) ->
  null.

after_context(AfterN, Rest) when AfterN > 0 ->
  TakeN = erlang:min(AfterN, length(Rest)),
  Slice = lists:sublist(Rest, TakeN),
  [openagentic_tool_grep_utils:to_bin(trim_cr(Line)) || Line <- Slice];
after_context(_AfterN, _Rest) ->
  null.

file_contains_match(Path, QueryRe) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case safe_utf8_lines(Bin) of
        {ok, Lines} -> lists:any(fun (Line) -> re:run(trim_cr(Line), QueryRe, [{capture, none}]) =:= match end, Lines);
        _ -> false
      end;
    _ -> false
  end.

trim_cr(Bin) when is_binary(Bin) ->
  case byte_size(Bin) of
    0 -> Bin;
    Size ->
      RestSize = Size - 1,
      case Bin of
        <<Rest:RestSize/binary, $>> -> Rest;
        _ -> Bin
      end
  end;
trim_cr(List) when is_list(List) ->
  trim_cr(iolist_to_binary(List)).

safe_utf8_lines(Bin0) when is_binary(Bin0) ->
  try
    Text = unicode:characters_to_binary(Bin0, utf8, utf8),
    {ok, binary:split(Text, <<"
">>, [global])}
  catch
    _:_ -> {error, bad_utf8}
  end.
