-module(openagentic_web_api_sse).

-include_lib("kernel/include/file.hrl").

-behaviour(cowboy_handler).

-export([init/2]).

%% SSE endpoint: tail a session's events.jsonl and stream as SSE.
%%
%% Route: /api/sessions/:sid/events

-define(POLL_MS, 250).
-define(KEEPALIVE_MS, 10000).

init(Req0, State0) ->
  State = ensure_map(State0),
  Root = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  SidBin = cowboy_req:binding(sid, Req0),
  Sid = ensure_list(SidBin),

  Last0 = cowboy_req:header(<<"last-event-id">>, Req0, undefined),
  LastSeq = parse_int(Last0, 0),

  Headers = #{
    <<"content-type">> => <<"text/event-stream; charset=utf-8">>,
    <<"cache-control">> => <<"no-store">>,
    <<"connection">> => <<"keep-alive">>
  },
  Req1 = cowboy_req:stream_reply(200, Headers, Req0),
  loop(Req1, Root, Sid, LastSeq, 0, <<>>, erlang:monotonic_time(millisecond)).

loop(Req, Root, Sid, LastSeq0, Offset0, Buf0, LastKeepaliveMs0) ->
  try
    Now = erlang:monotonic_time(millisecond),
    {LastSeq, Offset, Buf, Req2} = pump(Req, Root, Sid, LastSeq0, Offset0, Buf0),
    LastKeepaliveMs =
      case (Now - LastKeepaliveMs0) >= ?KEEPALIVE_MS of
        true ->
          _ = cowboy_req:stream_body(<<": ping\n\n">>, nofin, Req2),
          Now;
        false ->
          LastKeepaliveMs0
      end,
    timer:sleep(?POLL_MS),
    loop(Req2, Root, Sid, LastSeq, Offset, Buf, LastKeepaliveMs)
  catch
    _:_ ->
      ok
  end.

pump(Req, Root, Sid, LastSeq0, Offset0, Buf0) ->
  case session_events_path(Root, Sid) of
    {ok, Path} ->
      case file:read_file_info(Path) of
        {ok, Info} ->
          Size = Info#file_info.size,
          case Size > Offset0 of
            false ->
              {LastSeq0, Offset0, Buf0, Req};
            true ->
              case file:open(Path, [read, binary]) of
                {ok, Io} ->
                  _ = file:position(Io, Offset0),
                  {ok, Chunk} = file:read(Io, Size - Offset0),
                  _ = file:close(Io),
                  Offset1 = Size,
                  Buf1 = <<Buf0/binary, Chunk/binary>>,
                  stream_lines(Req, LastSeq0, Offset1, Buf1);
                _ ->
                  {LastSeq0, Offset0, Buf0, Req}
              end
          end;
        _ ->
          {LastSeq0, Offset0, Buf0, Req}
      end;
    _ ->
      {LastSeq0, Offset0, Buf0, Req}
  end.

stream_lines(Req0, LastSeq0, Offset, Buf0) ->
  Parts = binary:split(Buf0, <<"\n">>, [global]),
  case Parts of
    [] ->
      {LastSeq0, Offset, <<>>, Req0};
    _ ->
      %% Last part may be incomplete line (no trailing newline yet).
      {Lines, Tail} =
        case lists:last(Parts) of
          <<>> ->
            {lists:sublist(Parts, length(Parts) - 1), <<>>};
          T ->
            {lists:sublist(Parts, length(Parts) - 1), T}
        end,
      {Req1, LastSeq1} = lists:foldl(fun stream_one/2, {Req0, LastSeq0}, Lines),
      {LastSeq1, Offset, Tail, Req1}
  end.

stream_one(<<>>, Acc) ->
  Acc;
stream_one(Line0, {Req0, LastSeq0}) ->
  Line = string:trim(Line0),
  case byte_size(Line) of
    0 ->
      {Req0, LastSeq0};
    _ ->
      case decode(Line) of
        {ok, Obj} ->
          Seq = parse_int(maps:get(<<"seq">>, Obj, maps:get(seq, Obj, 0)), 0),
          Type = maps:get(<<"type">>, Obj, maps:get(type, Obj, <<"message">>)),
          case Seq > LastSeq0 of
            false ->
              {Req0, LastSeq0};
            true ->
              Payload =
                iolist_to_binary([
                  <<"id: ">>, integer_to_binary(Seq), <<"\n">>,
                  <<"event: ">>, to_bin(Type), <<"\n">>,
                  <<"data: ">>, Line, <<"\n\n">>
                ]),
              _ = cowboy_req:stream_body(Payload, nofin, Req0),
              {Req0, Seq}
          end;
        {error, _} ->
          {Req0, LastSeq0}
      end
  end.

session_events_path(Root0, Sid0) ->
  Root = ensure_list(Root0),
  Sid = ensure_list(Sid0),
  try
    Dir = openagentic_session_store:session_dir(Root, Sid),
    {ok, filename:join([Dir, "events.jsonl"])}
  catch
    _:_ -> {error, invalid_sid}
  end.

decode(Bin) ->
  try
    {ok, openagentic_json:decode(Bin)}
  catch
    _:_ -> {error, invalid}
  end.

parse_int(undefined, Default) -> Default;
parse_int(null, Default) -> Default;
parse_int(I, _Default) when is_integer(I) -> I;
parse_int(B, Default) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of
    I when is_integer(I) -> I;
    _ -> Default
  end;
parse_int(L, Default) when is_list(L) ->
  case (catch list_to_integer(string:trim(L))) of
    I when is_integer(I) -> I;
    _ -> Default
  end;
parse_int(_, Default) ->
  Default.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
