-module(openagentic_openai_responses_stream).

-export([collect_stream/3]).

-define(HTTPC_PROFILE, openagentic).

collect_stream(ReqId, TimeoutMs, OnDelta) ->
  Sse0 = openagentic_sse:new(),
  collect_loop(ReqId, TimeoutMs, Sse0, #{delta_text => <<>>, last_response => undefined, failed => undefined, on_delta => OnDelta}).

collect_loop(ReqId, TimeoutMs, SseState0, Acc0) ->
  receive
    {http, {ReqId, stream, Bin}} when is_binary(Bin) ->
      {SseState1, SseEvents} = openagentic_sse:feed(SseState0, Bin),
      Acc1 = handle_sse_events(SseEvents, Acc0),
      collect_loop(ReqId, TimeoutMs, SseState1, Acc1);
    {http, {ReqId, stream_end, _Trailers}} ->
      {_, FlushEvents} = openagentic_sse:end_of_input(SseState0),
      Acc1 = handle_sse_events(FlushEvents, Acc0),
      finalize_to_model_output(Acc1);
    {http, {ReqId, {error, Reason}}} ->
      {error, {http_stream_error, Reason}};
    {http, {ReqId, stream_start, _Headers}} ->
      collect_loop(ReqId, TimeoutMs, SseState0, Acc0);
    {http, {ReqId, {{_Vsn, Status, _ReasonPhrase}, Headers, Body}}} ->
      {error, {http_error, Status, Headers, Body}};
    _Other ->
      collect_loop(ReqId, TimeoutMs, SseState0, Acc0)
  after TimeoutMs ->
    _ = (catch httpc:cancel_request(ReqId, ?HTTPC_PROFILE)),
    {error, timeout}
  end.

handle_sse_events(SseEvents, Acc0) ->
  lists:foldl(fun handle_one_sse/2, Acc0, SseEvents).

handle_one_sse(#{data := <<>>}, Acc) ->
  Acc;
handle_one_sse(#{data := <<" [DONE]">>}, Acc) ->
  Acc;
handle_one_sse(#{data := <<"[DONE]">>}, Acc) ->
  Acc;
handle_one_sse(#{data := Data}, Acc0) ->
  case maps:get(failed, Acc0, undefined) of
    undefined ->
      try
        Obj = openagentic_json:decode(Data),
        TypeBin = openagentic_openai_responses_utils:to_bin(maps:get(<<"type">>, Obj, maps:get(type, Obj, <<>>))),
        handle_openai_type(TypeBin, Obj, Acc0)
      catch
        _:_ ->
          Acc0
      end;
    _ ->
      Acc0
  end.

handle_openai_type(<<"response.output_text.delta">>, Obj, Acc0) ->
  Delta = openagentic_openai_responses_utils:to_bin(maps:get(<<"delta">>, Obj, maps:get(delta, Obj, <<>>))),
  _ = maybe_emit_delta(Acc0, Delta),
  Prev = maps:get(delta_text, Acc0, <<>>),
  Acc0#{delta_text := <<Prev/binary, Delta/binary>>};
handle_openai_type(<<"response.completed">>, Obj, Acc0) ->
  Resp = maps:get(<<"response">>, Obj, maps:get(response, Obj, #{})),
  Acc0#{last_response := Resp};
handle_openai_type(<<"error">>, Obj, Acc0) ->
  Acc0#{failed := Obj};
handle_openai_type(_, _Obj, Acc0) ->
  Acc0.

maybe_emit_delta(Acc0, Delta) ->
  case maps:get(on_delta, Acc0, undefined) of
    F when is_function(F, 1) ->
      try
        F(Delta)
      catch
        _:_ -> ok
      end;
    _ -> ok
  end.

finalize_to_model_output(Acc0) ->
  case maps:get(failed, Acc0, undefined) of
    undefined ->
      Resp = maps:get(last_response, Acc0, undefined),
      case Resp of
        undefined ->
          {error, stream_ended_without_response_completed};
        _ ->
          ResponseId = openagentic_openai_responses_utils:to_bin(maps:get(<<"id">>, Resp, maps:get(id, Resp, undefined))),
          Usage = maps:get(<<"usage">>, Resp, maps:get(usage, Resp, undefined)),
          OutputItems = maps:get(<<"output">>, Resp, maps:get(output, Resp, [])),
          AssistantText =
            case openagentic_openai_responses_normalize:parse_assistant_text(OutputItems) of
              <<>> -> maps:get(delta_text, Acc0, <<>>);
              T -> T
            end,
          ToolCalls = openagentic_openai_responses_normalize:parse_tool_calls(OutputItems),
          {ok, #{
            assistant_text => AssistantText,
            tool_calls => ToolCalls,
            usage => openagentic_openai_responses_utils:ensure_map(Usage),
            response_id => ResponseId
          }}
      end;
    Err ->
      {error, {provider_error, Err}}
  end.
