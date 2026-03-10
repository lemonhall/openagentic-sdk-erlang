-module(openagentic_testing_provider_monitoring_slow).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req) ->
  timer:sleep(700),
  openagentic_testing_provider_monitoring_success:complete(Req).
