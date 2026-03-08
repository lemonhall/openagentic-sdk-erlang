-module(openagentic_session_store_read).

-export([infer_next_seq/1, read_events/2]).

read_events(RootDir0, SessionId0) ->
  RootDir = openagentic_session_store_utils:ensure_list(RootDir0),
  SessionId = openagentic_session_store_utils:ensure_list(SessionId0),
  Path = filename:join([openagentic_session_store_layout:session_dir(RootDir, SessionId), "events.jsonl"]),
  case file:read_file(Path) of
    {ok, Bin} -> parse_lines([Line || Line <- binary:split(Bin, <<"\n">>, [global]), Line =/= <<>>], []);
    _ -> []
  end.

parse_lines([], Acc) ->
  lists:reverse(Acc);
parse_lines([Line | Rest], Acc) ->
  try parse_lines(Rest, [openagentic_json:decode(Line) | Acc])
  catch
    _:_ -> lists:reverse(Acc)
  end.

infer_next_seq(Path) ->
  case file:read_file(Path) of
    {ok, Bin} -> infer_next_seq_lines(lists:reverse(binary:split(Bin, <<"\n">>, [global])));
    _ -> 0
  end.

infer_next_seq_lines([]) -> 0;
infer_next_seq_lines([<<>> | Rest]) -> infer_next_seq_lines(Rest);
infer_next_seq_lines([Line | Rest]) ->
  try
    Obj = openagentic_json:decode(Line),
    case maps:get(<<"seq">>, Obj, maps:get(seq, Obj, undefined)) of
      undefined -> infer_next_seq_lines(Rest);
      Seq when is_integer(Seq) -> Seq;
      SeqBin when is_binary(SeqBin) -> case (catch binary_to_integer(SeqBin)) of I when is_integer(I) -> I; _ -> infer_next_seq_lines(Rest) end;
      _ -> infer_next_seq_lines(Rest)
    end
  catch
    _:_ -> 0
  end.
