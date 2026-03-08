-module(openagentic_web_e2e_online_sse_support).
-export([sse_wait_done/2]).

-include_lib("eunit/include/eunit.hrl").

-define(HTTPC_PROFILE, openagentic_web_e2e).

sse_wait_done(Url0, TimeoutMs) ->
  Url = openagentic_web_e2e_online_test_support:ensure_list(Url0),
  Headers = [{"accept", "text/event-stream"}],
  HttpOptions = [{timeout, TimeoutMs}],
  Opts = [{sync, false}, {stream, self}, {body_format, binary}],
  {ok, ReqId} = httpc:request(get, {Url, Headers}, HttpOptions, Opts, ?HTTPC_PROFILE),
  receive_done(ReqId, <<>>, undefined, undefined, TimeoutMs).

receive_done(ReqId, Buf0, CurEvent0, CurId0, TimeoutMs) ->
  receive
    {http, {ReqId, stream_start, _Headers}} ->
      receive_done(ReqId, Buf0, CurEvent0, CurId0, TimeoutMs);
    {http, {ReqId, stream, Bin}} ->
      Buf1 = <<Buf0/binary, Bin/binary>>,
      {Buf2, CurEvent, CurId, Done} = sse_parse(Buf1, CurEvent0, CurId0),
      case Done of
        {done, Obj} ->
          %% Ensure we got workflow.done and it's not a raw crash tuple.
          Type = maps:get(<<"type">>, Obj, <<>>),
          ?assertEqual(<<"workflow.done">>, Type),
          Status = maps:get(<<"status">>, Obj, maps:get(status, Obj, <<>>)),
          case Status of
            <<"failed">> ->
              Final = maps:get(<<"final_text">>, Obj, maps:get(final_text, Obj, <<>>)),
              Stack = maps:get(<<"stacktrace">>, Obj, maps:get(stacktrace, Obj, undefined)),
              erlang:error({workflow_failed, Final, Stack});
            _ ->
              ok
          end,
          {ok, ReqId};
        _ ->
          receive_done(ReqId, Buf2, CurEvent, CurId, TimeoutMs)
      end;
    {http, {ReqId, stream_end, _Trailers}} ->
      ?assert(false);
    {http, {ReqId, {error, Reason}}} ->
      erlang:error({http_error, Reason})
  after TimeoutMs ->
    erlang:error(timeout)
  end.

sse_parse(Buf0, CurEvent0, CurId0) ->
  %% Parse one or more SSE frames separated by "\n\n".
  case binary:match(Buf0, <<"\n\n">>) of
    nomatch ->
      {Buf0, CurEvent0, CurId0, none};
    {Pos, _Len} ->
      Frame = binary:part(Buf0, 0, Pos),
      Rest = binary:part(Buf0, Pos + 2, byte_size(Buf0) - (Pos + 2)),
      {CurEvent1, CurId1, Done0} = sse_parse_frame(Frame, CurEvent0, CurId0),
      case Done0 of
        {done, _} = Done ->
          {Rest, CurEvent1, CurId1, Done};
        _ ->
          sse_parse(Rest, CurEvent1, CurId1)
      end
  end.

sse_parse_frame(Frame0, CurEvent0, CurId0) ->
  Frame = string:trim(Frame0),
  Lines = binary:split(Frame, <<"\n">>, [global]),
  lists:foldl(fun sse_line/2, {CurEvent0, CurId0, none}, Lines).

sse_line(<<>>, Acc) ->
  Acc;
sse_line(<<$:,_/binary>>, Acc) ->
  %% comment/keepalive
  Acc;
sse_line(Line0, {CurEvent0, CurId0, Done0}) ->
  Line = string:trim(Line0),
  case Line of
    <<"event: ", Ev/binary>> ->
      {string:trim(Ev), CurId0, Done0};
    <<"id: ", Id/binary>> ->
      {CurEvent0, string:trim(Id), Done0};
    <<"data: ", Data0/binary>> ->
      Data = string:trim(Data0),
      case CurEvent0 of
        <<"workflow.done">> ->
          case (catch openagentic_json:decode(Data)) of
            Obj when is_map(Obj) ->
              {CurEvent0, CurId0, {done, Obj}};
            _ ->
              {CurEvent0, CurId0, Done0}
          end;
        _ ->
          {CurEvent0, CurId0, Done0}
      end;
    _ ->
      {CurEvent0, CurId0, Done0}
  end.

%% ---- HTTP JSON ----

