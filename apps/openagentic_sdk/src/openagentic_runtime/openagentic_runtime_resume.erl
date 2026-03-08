-module(openagentic_runtime_resume).
-export([trim_events_for_resume/3,trim_events_for_resume_loop/5,safe_event_len/1,infer_previous_response_id/1,infer_previous_response_id_loop/1]).

trim_events_for_resume(Events0, MaxEvents0, MaxBytes0) ->
  Events = openagentic_runtime_utils:ensure_list(Events0),
  MaxEvents = erlang:max(0, MaxEvents0),
  MaxBytes = erlang:max(0, MaxBytes0),
  case {MaxEvents =< 0, MaxBytes =< 0} of
    {true, true} ->
      Events;
    _ ->
      trim_events_for_resume_loop(lists:reverse(Events), MaxEvents, MaxBytes, [], 0)
  end.

trim_events_for_resume_loop([], _MaxEvents, _MaxBytes, Acc, _Bytes) ->
  lists:reverse(Acc);
trim_events_for_resume_loop([E | Rest], MaxEvents, MaxBytes, Acc0, Bytes0) ->
  case (MaxEvents > 0 andalso length(Acc0) >= MaxEvents) of
    true -> lists:reverse(Acc0);
    false ->
      Approx = safe_event_len(E),
      case (MaxBytes > 0 andalso (Bytes0 + Approx) > MaxBytes andalso Acc0 =/= []) of
        true ->
          lists:reverse(Acc0);
        false ->
          trim_events_for_resume_loop(Rest, MaxEvents, MaxBytes, [E | Acc0], Bytes0 + Approx)
      end
  end.

safe_event_len(E) ->
  try
    byte_size(openagentic_json:encode(openagentic_runtime_utils:ensure_map(E)))
  catch
    _:_ -> 0
  end.

infer_previous_response_id(Events0) ->
  Events = openagentic_runtime_utils:ensure_list(Events0),
  infer_previous_response_id_loop(lists:reverse(Events)).

infer_previous_response_id_loop([]) ->
  undefined;
infer_previous_response_id_loop([E0 | Rest]) ->
  E = openagentic_runtime_utils:ensure_map(E0),
  Type = openagentic_runtime_utils:to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  case Type of
    <<"result">> ->
      Resp0 = maps:get(<<"response_id">>, E, maps:get(response_id, E, undefined)),
      Resp = string:trim(openagentic_runtime_utils:to_bin(Resp0)),
      case byte_size(Resp) > 0 of
        true -> Resp;
        false -> infer_previous_response_id_loop(Rest)
      end;
    _ -> infer_previous_response_id_loop(Rest)
  end.
