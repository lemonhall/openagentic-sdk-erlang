-module(openagentic_model_input_test).

-include_lib("eunit/include/eunit.hrl").

build_responses_input_pairs_tool_calls_test() ->
  Use = #{type => <<"tool.use">>, tool_use_id => <<"call_1">>, name => <<"Read">>, input => #{path => <<"a.txt">>}},
  Res = #{type => <<"tool.result">>, tool_use_id => <<"call_1">>, is_error => false, output => #{ok => true}},
  Items = openagentic_model_input:build_responses_input([Use, Res]),
  ?assertEqual(
    [
      #{type => <<"function_call">>, call_id => <<"call_1">>, name => <<"Read">>, arguments => <<"{\"path\":\"a.txt\"}">>},
      #{type => <<"function_call_output">>, call_id => <<"call_1">>, output => <<"{\"ok\":true}">>}
    ],
    Items
  ).

build_responses_input_drops_unpaired_tool_use_test() ->
  UseOnly = #{type => <<"tool.use">>, tool_use_id => <<"call_2">>, name => <<"Read">>, input => #{path => <<"b.txt">>}},
  Items = openagentic_model_input:build_responses_input([UseOnly]),
  ?assertEqual([], Items).

build_responses_input_drops_unpaired_tool_result_test() ->
  ResOnly = #{type => <<"tool.result">>, tool_use_id => <<"call_3">>, is_error => false, output => #{ok => true}},
  Items = openagentic_model_input:build_responses_input([ResOnly]),
  ?assertEqual([], Items).

