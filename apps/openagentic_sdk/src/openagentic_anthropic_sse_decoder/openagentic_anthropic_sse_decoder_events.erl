-module(openagentic_anthropic_sse_decoder_events).

-export([on_sse_event/2]).

on_sse_event(Ev0, State0) ->
  State = openagentic_anthropic_sse_decoder_utils:ensure_map(State0),
  Failed = maps:get(failed, State, undefined),
  Done = maps:get(done, State, false),
  case {Failed, Done} of
    {undefined, false} ->
      Ev = openagentic_anthropic_sse_decoder_utils:ensure_map(Ev0),
      EventType = openagentic_anthropic_sse_decoder_utils:bin_trim(maps:get(event, Ev, <<>>)),
      DataBin = openagentic_anthropic_sse_decoder_utils:bin_trim(maps:get(data, Ev, <<>>)),
      case DataBin of
        <<>> -> {State, []};
        _ ->
          Obj = openagentic_anthropic_sse_decoder_state:decode_json_or_undefined(DataBin),
          handle_event(EventType, Obj, State)
      end;
    _ ->
      {State, []}
  end.

handle_event(<<"message_start">>, Obj, State0) ->
  Msg = openagentic_anthropic_sse_decoder_utils:ensure_map(maps:get(<<"message">>, Obj, maps:get(message, Obj, #{}))),
  MsgId = openagentic_anthropic_sse_decoder_utils:bin_trim(maps:get(<<"id">>, Msg, maps:get(id, Msg, <<>>))),
  Usage = maps:get(<<"usage">>, Msg, maps:get(usage, Msg, undefined)),
  State1 = State0#{
    message_id := case MsgId of <<>> -> maps:get(message_id, State0, undefined); _ -> MsgId end,
    usage := openagentic_anthropic_sse_decoder_state:ensure_usage(Usage)
  },
  {State1, []};
handle_event(<<"content_block_start">>, Obj, State0) ->
  Index = openagentic_anthropic_sse_decoder_utils:pick_int(Obj, [<<"index">>, index], length(maps:get(blocks, State0, []))),
  BlockObj = openagentic_anthropic_sse_decoder_utils:ensure_map(
    openagentic_anthropic_sse_decoder_utils:pick_first(Obj, [<<"content_block">>, content_block, <<"contentBlock">>, contentBlock])
  ),
  Type = openagentic_anthropic_sse_decoder_utils:bin_trim(
    openagentic_anthropic_sse_decoder_utils:pick_first(BlockObj, [<<"type">>, type])
  ),
  State1 = State0#{current_index := Index},
  case Type of
    <<"text">> -> {openagentic_anthropic_sse_decoder_state:ensure_block_at(Index, {text, []}, State1), []};
    <<"tool_use">> ->
      Id = openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:pick_first(BlockObj, [<<"id">>, id])),
      Name = openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:pick_first(BlockObj, [<<"name">>, name])),
      {openagentic_anthropic_sse_decoder_state:ensure_block_at(Index, {tool_use, Id, Name, []}, State1), []};
    _ -> {State1, []}
  end;
handle_event(<<"content_block_delta">>, Obj, State0) ->
  Index = openagentic_anthropic_sse_decoder_utils:pick_int(Obj, [<<"index">>, index], maps:get(current_index, State0, -1)),
  Delta = openagentic_anthropic_sse_decoder_utils:ensure_map(openagentic_anthropic_sse_decoder_utils:pick_first(Obj, [<<"delta">>, delta])),
  DeltaType = openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:pick_first(Delta, [<<"type">>, type])),
  case DeltaType of
    <<"text_delta">> ->
      Text = openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:pick_first(Delta, [<<"text">>, text])),
      State1 = openagentic_anthropic_sse_decoder_state:append_text_delta(Index, Text, State0),
      case byte_size(Text) > 0 of true -> {State1, [Text]}; false -> {State1, []} end;
    <<"input_json_delta">> ->
      Part = openagentic_anthropic_sse_decoder_utils:bin_trim(
        openagentic_anthropic_sse_decoder_utils:pick_first(Delta, [<<"partial_json">>, partial_json, <<"partialJson">>, partialJson])
      ),
      {openagentic_anthropic_sse_decoder_state:append_input_json_delta(Index, Part, State0), []};
    _ ->
      {State0, []}
  end;
handle_event(<<"message_delta">>, Obj, State0) ->
  Delta = openagentic_anthropic_sse_decoder_utils:ensure_map(openagentic_anthropic_sse_decoder_utils:pick_first(Obj, [<<"delta">>, delta])),
  Stop = openagentic_anthropic_sse_decoder_utils:bin_trim(
    openagentic_anthropic_sse_decoder_utils:pick_first(Delta, [<<"stop_reason">>, stop_reason, <<"stopReason">>, stopReason])
  ),
  Usage = openagentic_anthropic_sse_decoder_state:ensure_usage(openagentic_anthropic_sse_decoder_utils:pick_first(Obj, [<<"usage">>, usage])),
  State1 = State0#{
    stop_reason := case Stop of <<>> -> maps:get(stop_reason, State0, undefined); _ -> Stop end,
    usage := case Usage of undefined -> maps:get(usage, State0, undefined); _ -> Usage end
  },
  {State1, []};
handle_event(<<"message_stop">>, _Obj, State0) ->
  {State0#{done := true}, []};
handle_event(<<"error">>, Obj, State0) ->
  Err = openagentic_anthropic_sse_decoder_utils:ensure_map(openagentic_anthropic_sse_decoder_utils:pick_first(Obj, [<<"error">>, error])),
  Msg0 = openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:pick_first(Err, [<<"message">>, message])),
  Msg = case Msg0 of <<>> -> openagentic_anthropic_sse_decoder_utils:bin_trim(openagentic_anthropic_sse_decoder_utils:to_bin(Obj)); _ -> Msg0 end,
  {State0#{failed := Msg, done := true}, []};
handle_event(_Other, _Obj, State0) ->
  {State0, []}.
