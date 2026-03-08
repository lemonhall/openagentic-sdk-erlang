-module(openagentic_testing_provider_monitoring_invalid).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req) ->
  {ok,
   #{
     assistant_text => <<"This is not valid monitoring delivery JSON.">>,
     tool_calls => [],
     response_id => <<"resp_monitoring_invalid_1">>,
     usage => #{}
   }}.
