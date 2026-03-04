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

build_responses_input_includes_tool_errors_test() ->
  Use = #{type => <<"tool.use">>, tool_use_id => <<"call_4">>, name => <<"Bash">>, input => #{command => <<"echo hi">>}},
  Res = #{
    type => <<"tool.result">>,
    tool_use_id => <<"call_4">>,
    is_error => true,
    error_type => <<"PermissionDenied">>,
    error_message => <<"user denied">>
  },
  Items = openagentic_model_input:build_responses_input([Use, Res]),
  ?assertEqual(2, length(Items)),
  [Call, Out] = Items,
  ?assertMatch(
    #{type := <<"function_call">>, call_id := <<"call_4">>, name := <<"Bash">>, arguments := <<"{\"command\":\"echo hi\"}">>},
    Call
  ),
  ?assertMatch(#{type := <<"function_call_output">>, call_id := <<"call_4">>}, Out),
  OutJson = openagentic_json:decode(maps:get(output, Out)),
  Err = maps:get(<<"error">>, OutJson),
  ?assertEqual(<<"PermissionDenied">>, maps:get(<<"type">>, Err)),
  ?assertEqual(<<"user denied">>, maps:get(<<"message">>, Err)).
