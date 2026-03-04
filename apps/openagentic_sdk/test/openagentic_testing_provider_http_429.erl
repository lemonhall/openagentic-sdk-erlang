-module(openagentic_testing_provider_http_429).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req0) ->
  {error, {http_error, 429, [{<<"retry-after">>, <<"100ms">>}], <<"oops">>}}.

