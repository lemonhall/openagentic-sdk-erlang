-module(openagentic_openai_responses_test).

-include_lib("eunit/include/eunit.hrl").

offline_parse_output_items_test() ->
  OutputItems = [
    #{
      <<"type">> => <<"function_call">>,
      <<"call_id">> => <<"call_1">>,
      <<"name">> => <<"Echo">>,
      <<"arguments">> => <<"{\"text\":\"Hello\"}">>
    },
    #{
      <<"type">> => <<"message">>,
      <<"content">> => [
        #{<<"type">> => <<"output_text">>, <<"text">> => <<"Done.">>}
      ]
    }
  ],
  Text = openagentic_openai_responses:parse_assistant_text_for_test(OutputItems),
  ToolCalls = openagentic_openai_responses:parse_tool_calls_for_test(OutputItems),
  ?assertEqual(<<"Done.">>, Text),
  ?assertMatch([#{tool_use_id := <<"call_1">>, name := <<"Echo">>, arguments := _}], ToolCalls),
  [TC] = ToolCalls,
  ?assertEqual(<<"Hello">>, maps:get(<<"text">>, maps:get(arguments, TC))).

