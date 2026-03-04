-module(openagentic_testing_provider_missing_required).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req0) ->
  {error, {missing_required, [{error, {missing, api_key}}]}}.

