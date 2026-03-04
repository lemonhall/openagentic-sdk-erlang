-module(openagentic_testing_provider_stream_fail).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req0) ->
  {error, stream_ended_without_response_completed}.

