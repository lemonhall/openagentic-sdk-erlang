-module(openagentic_sse_test).

-include_lib("eunit/include/eunit.hrl").

simple_sse_decode_test() ->
  S0 = openagentic_sse:new(),
  Chunk =
    <<
      ": ping\r\n",
      "event: response.output_text.delta\r\n",
      "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}\r\n",
      "\r\n",
      "data: [DONE]\r\n",
      "\r\n"
    >>,
  {S1, Events} = openagentic_sse:feed(S0, Chunk),
  ?assert(is_map(S1)),
  ?assertEqual(
    [
      #{
        event => <<"response.output_text.delta">>,
        data => <<"{\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}">>
      },
      #{event => undefined, data => <<"[DONE]">>}
    ],
    Events
  ).

