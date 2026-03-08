-module(openagentic_testing_provider_monitoring_auth_expired).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req) ->
  {error, {http_error, 401, [], <<"session expired; login required">>}}.
