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

request_payload_includes_store_default_true_test() ->
  Payload =
    openagentic_openai_responses:request_payload_for_test(
      <<"gpt-test">>,
      [],
      [],
      undefined,
      #{}
    ),
  ?assertEqual(true, maps:get(store, Payload)).

request_payload_store_override_false_test() ->
  Payload =
    openagentic_openai_responses:request_payload_for_test(
      <<"gpt-test">>,
      [],
      [],
      undefined,
      #{store => false}
    ),
  ?assertEqual(false, maps:get(store, Payload)).

headers_authorization_uses_bearer_test() ->
  H = openagentic_openai_responses:build_headers_for_test(<<"authorization">>, <<"sk-test">>, false),
  ?assert(lists:member({"authorization", "Bearer sk-test"}, H)).

headers_custom_header_uses_raw_key_test() ->
  H = openagentic_openai_responses:build_headers_for_test(<<"x-api-key">>, <<"sk-test">>, false),
  ?assert(lists:member({"x-api-key", "sk-test"}, H)).
