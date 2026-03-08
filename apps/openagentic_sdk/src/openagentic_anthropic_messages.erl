-module(openagentic_anthropic_messages).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req) ->
  openagentic_anthropic_messages_complete:complete(Req).
