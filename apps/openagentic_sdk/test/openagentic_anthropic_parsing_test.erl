-module(openagentic_anthropic_parsing_test).

-include_lib("eunit/include/eunit.hrl").

responses_input_to_messages_builds_expected_blocks_test() ->
  Input = [
    #{role => <<"system">>, content => <<"SYS">>},
    #{role => <<"user">>, content => <<"hi">>},
    #{type => <<"function_call">>, call_id => <<"call_1">>, name => <<"Read">>, arguments => <<"{\"file_path\":\"a.txt\"}">>},
    #{type => <<"function_call_output">>, call_id => <<"call_1">>, output => <<"OK">>}
  ],
  {System, Messages} = openagentic_anthropic_parsing:responses_input_to_messages(Input),
  ?assertEqual(<<"SYS">>, System),
  ?assertEqual(3, length(Messages)),
  [M1, M2, M3] = Messages,
  ?assertEqual(<<"user">>, maps:get(<<"role">>, M1)),
  ?assert(maps:get(<<"content">>, M1) =/= undefined),
  ?assertEqual(<<"assistant">>, maps:get(<<"role">>, M2)),
  ?assertEqual(<<"user">>, maps:get(<<"role">>, M3)),
  ok.

responses_tools_to_anthropic_tools_test() ->
  Tools = [
    #{<<"name">> => <<"Read">>, <<"description">> => <<"d">>, <<"parameters">> => #{<<"type">> => <<"object">>, <<"properties">> => #{}}}
  ],
  Out = openagentic_anthropic_parsing:responses_tools_to_anthropic_tools(Tools),
  ?assertEqual(1, length(Out)),
  [T] = Out,
  ?assertEqual(<<"Read">>, maps:get(<<"name">>, T)),
  ?assertEqual(<<"d">>, maps:get(<<"description">>, T)),
  ?assert(is_map(maps:get(<<"input_schema">>, T))),
  ok.

anthropic_content_to_model_output_maps_text_and_tool_calls_test() ->
  Content = [
    #{<<"type">> => <<"text">>, <<"text">> => <<"Hello">>},
    #{<<"type">> => <<"tool_use">>, <<"id">> => <<"tu1">>, <<"name">> => <<"Read">>, <<"input">> => #{<<"file_path">> => <<"a.txt">>}}
  ],
  Out = openagentic_anthropic_parsing:anthropic_content_to_model_output(Content, #{}, <<"msg1">>),
  ?assertEqual(<<"Hello">>, maps:get(assistant_text, Out)),
  ?assertEqual(<<"msg1">>, maps:get(response_id, Out)),
  Calls = maps:get(tool_calls, Out),
  ?assertEqual(1, length(Calls)),
  [C] = Calls,
  ?assertEqual(<<"tu1">>, maps:get(tool_use_id, C)),
  ?assertEqual(<<"Read">>, maps:get(name, C)),
  Args = maps:get(arguments, C),
  ?assertEqual(<<"a.txt">>, maps:get(<<"file_path">>, Args)),
  ok.

