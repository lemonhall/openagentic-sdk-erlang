-module(openagentic_session_store).

-include_lib("kernel/include/file.hrl").

-export([
  create_session/2,
  append_event/3,
  read_events/2,
  session_dir/2
]).

create_session(RootDir0, Metadata) ->
  RootDir = ensure_list(RootDir0),
  SessionId = new_session_id(),
  Dir = session_dir(RootDir, SessionId),
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  CreatedAt = erlang:system_time(second) * 1.0,
  Meta = #{
    session_id => to_bin(SessionId),
    created_at => CreatedAt,
    metadata => ensure_map(Metadata)
  },
  MetaJson = openagentic_json:to_json_term(Meta),
  MetaBin = openagentic_json:encode(MetaJson),
  ok = write_text(filename:join([Dir, "meta.json"]), <<MetaBin/binary, "\n">>),
  {ok, SessionId}.

append_event(RootDir0, SessionId0, Event0) ->
  RootDir = ensure_list(RootDir0),
  SessionId = ensure_list(SessionId0),
  Dir = session_dir(RootDir, SessionId),
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  Path = filename:join([Dir, "events.jsonl"]),
  ok = repair_truncated_tail(Path),
  NextSeq = infer_next_seq(Path) + 1,
  Ts = erlang:system_time(millisecond) / 1000.0,
  Event1 = with_meta(Event0, NextSeq, Ts),
  Event = openagentic_json:to_json_term(Event1),
  Line = openagentic_json:encode(Event),
  ok = append_text(Path, <<Line/binary, "\n">>),
  {ok, Event}.

read_events(RootDir0, SessionId0) ->
  RootDir = ensure_list(RootDir0),
  SessionId = ensure_list(SessionId0),
  Dir = session_dir(RootDir, SessionId),
  Path = filename:join([Dir, "events.jsonl"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      Lines = binary:split(Bin, <<"\n">>, [global]),
      NonBlank = [L || L <- Lines, L =/= <<>>],
      parse_lines(NonBlank, []);
    _ ->
      []
  end.

session_dir(RootDir0, SessionId0) ->
  RootDir = ensure_list(RootDir0),
  SessionId = ensure_list(SessionId0),
  Sid = string:trim(SessionId),
  case is_valid_sid(Sid) of
    true -> filename:join([RootDir, "sessions", Sid]);
    false -> erlang:error({invalid_session_id, Sid})
  end.

%% internal
parse_lines([], Acc) ->
  lists:reverse(Acc);
parse_lines([Line | Rest], Acc) ->
  try
    Obj = openagentic_json:decode(Line),
    parse_lines(Rest, [Obj | Acc])
  catch
    _:_ ->
      %% Best-effort: stop at first parse failure (likely truncated tail)
      lists:reverse(Acc)
  end.

with_meta(E, Seq, Ts) when is_map(E) ->
  E#{seq => Seq, ts => Ts};
with_meta(E, Seq, Ts) ->
  #{type => <<"unknown">>, value => E, seq => Seq, ts => Ts}.

infer_next_seq(Path) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      Lines = lists:reverse(binary:split(Bin, <<"\n">>, [global])),
      infer_next_seq_lines(Lines);
    _ ->
      0
  end.

infer_next_seq_lines([]) -> 0;
infer_next_seq_lines([<<>> | Rest]) -> infer_next_seq_lines(Rest);
infer_next_seq_lines([Line | Rest]) ->
  try
    Obj = openagentic_json:decode(Line),
    case maps:get(<<"seq">>, Obj, maps:get(seq, Obj, undefined)) of
      undefined -> infer_next_seq_lines(Rest);
      S when is_integer(S) -> S;
      SBin when is_binary(SBin) ->
        case (catch binary_to_integer(SBin)) of
          I when is_integer(I) -> I;
          _ -> infer_next_seq_lines(Rest)
        end;
      _ ->
        infer_next_seq_lines(Rest)
    end
  catch
    _:_ ->
      0
  end.

repair_truncated_tail(Path) ->
  case file:read_file_info(Path) of
    {ok, #file_info{size = Size}} when is_integer(Size), Size > 0 ->
      case file:open(Path, [read, binary]) of
        {ok, Io} ->
          Res =
            case file:position(Io, {eof, -1}) of
              {ok, _Pos} ->
                case file:read(Io, 1) of
                  {ok, <<$\n>>} ->
                    ok;
                  _ ->
                    file:close(Io),
                    truncate_to_last_newline(Path)
                end;
              _ ->
                ok
            end,
          _ = file:close(Io),
          Res;
        _ ->
          ok
      end;
    _ ->
      ok
  end.

truncate_to_last_newline(Path) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case last_newline_pos(Bin) of
        -1 ->
          file:write_file(Path, <<>>);
        Pos ->
          Keep = binary:part(Bin, 0, Pos + 1),
          file:write_file(Path, Keep)
      end;
    _ ->
      ok
  end.

last_newline_pos(Bin) ->
  last_newline_pos(Bin, byte_size(Bin) - 1).

last_newline_pos(_Bin, Idx) when Idx < 0 -> -1;
last_newline_pos(Bin, Idx) ->
  case binary:at(Bin, Idx) of
    $\n -> Idx;
    _ -> last_newline_pos(Bin, Idx - 1)
  end.

new_session_id() ->
  Bytes = crypto:strong_rand_bytes(16),
  hex_lower(Bytes).

hex_lower(Bin) ->
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bin]).

is_valid_sid(Sid) when is_list(Sid) ->
  length(Sid) =:= 32 andalso lists:all(fun is_hex/1, Sid).

is_hex(C) when C >= $0, C =< $9 -> true;
is_hex(C) when C >= $a, C =< $f -> true;
is_hex(C) when C >= $A, C =< $F -> true;
is_hex(_) -> false.

write_text(Path, Bin) ->
  file:write_file(Path, Bin).

append_text(Path, Bin) ->
  case file:open(Path, [append, binary]) of
    {ok, Io} ->
      ok = file:write(Io, Bin),
      file:close(Io);
    Err ->
      Err
  end.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
