-module(openagentic_anthropic_sse_decoder).

-export([new/0, on_sse_event/2, finish/1]).

new() ->
  openagentic_anthropic_sse_decoder_state:new().

on_sse_event(Ev, State) ->
  openagentic_anthropic_sse_decoder_events:on_sse_event(Ev, State).

finish(State) ->
  openagentic_anthropic_sse_decoder_state:finish(State).
