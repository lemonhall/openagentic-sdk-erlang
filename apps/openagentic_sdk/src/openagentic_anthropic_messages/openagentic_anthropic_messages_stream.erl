-module(openagentic_anthropic_messages_stream).

-export([collect_stream/3]).

-define(HTTPC_PROFILE, openagentic).

collect_stream(ReqId, TimeoutMs, OnDelta) ->
  Sse0 = openagentic_sse:new(),
  Dec0 = openagentic_anthropic_sse_decoder:new(),
  collect_loop(ReqId, TimeoutMs, Sse0, Dec0, OnDelta).

collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta) ->
  receive
    {http, {ReqId, stream, Bin}} when is_binary(Bin) ->
      {SseState1, SseEvents} = openagentic_sse:feed(SseState0, Bin),
      {Dec1, _} = handle_sse_events(SseEvents, Dec0, OnDelta),
      collect_loop(ReqId, TimeoutMs, SseState1, Dec1, OnDelta);
    {http, {ReqId, stream_end, _Trailers}} ->
      {_, FlushEvents} = openagentic_sse:end_of_input(SseState0),
      {Dec1, _} = handle_sse_events(FlushEvents, Dec0, OnDelta),
      openagentic_anthropic_sse_decoder:finish(Dec1);
    {http, {ReqId, {error, Reason}}} ->
      {error, {http_stream_error, Reason}};
    {http, {ReqId, stream_start, _Headers}} ->
      collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta);
    {http, {ReqId, {{_Vsn, Status, _ReasonPhrase}, Headers, Body}}} ->
      {error, {http_error, Status, Headers, Body}};
    _Other ->
      collect_loop(ReqId, TimeoutMs, SseState0, Dec0, OnDelta)
  after TimeoutMs ->
    _ = (catch httpc:cancel_request(ReqId, ?HTTPC_PROFILE)),
    {error, timeout}
  end.

handle_sse_events(SseEvents, Dec0, OnDelta) ->
  lists:foldl(
    fun (Ev, {DecAcc0, _}) ->
      {DecAcc1, Deltas} = openagentic_anthropic_sse_decoder:on_sse_event(Ev, DecAcc0),
      _ =
        case OnDelta of
          F when is_function(F, 1) ->
            lists:foreach(fun (D) -> (catch F(D)) end, Deltas),
            ok;
          _ ->
            ok
        end,
      {DecAcc1, ok}
    end,
    {Dec0, ok},
    SseEvents
  ).
