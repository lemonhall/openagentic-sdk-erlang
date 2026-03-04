-module(openagentic_anthropic_sse_decoder_test).

-include_lib("eunit/include/eunit.hrl").

stream_decodes_text_deltas_and_tool_use_test() ->
  D0 = openagentic_anthropic_sse_decoder:new(),

  {D1, _} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"message_start">>,
        data => <<"{\"message\":{\"id\":\"msg1\",\"usage\":{\"input_tokens\":1}}}">>
      },
      D0
    ),

  {D2, _} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"content_block_start">>,
        data => <<"{\"index\":0,\"content_block\":{\"type\":\"text\"}}">>
      },
      D1
    ),

  {D3, Deltas1} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"content_block_delta">>,
        data => <<"{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}">>
      },
      D2
    ),
  ?assertEqual([<<"Hello">>], Deltas1),

  {D4, _} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"content_block_start">>,
        data => <<"{\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu1\",\"name\":\"Read\"}}">>
      },
      D3
    ),

  {D5, _} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"content_block_delta">>,
        data => <<"{\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"file_path\\\":\\\"a.txt\\\"}\"}}">>
      },
      D4
    ),

  {D6, _} =
    openagentic_anthropic_sse_decoder:on_sse_event(
      #{
        event => <<"message_stop">>,
        data => <<"{}">>
      },
      D5
    ),

  {ok, Out} = openagentic_anthropic_sse_decoder:finish(D6),
  ?assertEqual(<<"Hello">>, maps:get(assistant_text, Out)),
  ?assertEqual(<<"msg1">>, maps:get(response_id, Out)),
  Calls = maps:get(tool_calls, Out),
  ?assertEqual(1, length(Calls)),
  [C] = Calls,
  ?assertEqual(<<"tu1">>, maps:get(tool_use_id, C)),
  Args = maps:get(arguments, C),
  ?assertEqual(<<"a.txt">>, maps:get(<<"file_path">>, Args)),
  ok.

