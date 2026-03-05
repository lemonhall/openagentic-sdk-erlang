-module(openagentic_web_api_health).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
  Body = openagentic_json:encode_safe(#{ok => true}),
  Req1 =
    cowboy_req:reply(
      200,
      #{<<"content-type">> => <<"application/json">>, <<"cache-control">> => <<"no-store">>},
      Body,
      Req0
    ),
  {ok, Req1, State}.
