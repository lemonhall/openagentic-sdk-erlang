-module(openagentic_openai_chat_completions_test).

-include_lib("eunit/include/eunit.hrl").

responses_input_to_chat_messages_merges_tool_calls_test() ->
  Input = [
    #{role => <<"user">>, content => <<"hi">>},
    #{type => <<"function_call">>, call_id => <<"c1">>, name => <<"Read">>, arguments => <<"{\"file_path\":\"x\"}">>},
    #{type => <<"function_call_output">>, call_id => <<"c1">>, output => <<"\"ok\"">>},
    #{role => <<"assistant">>, content => <<"done">>}
  ],
  Msgs = openagentic_openai_chat_completions:responses_input_to_chat_messages_for_test(Input),
  ?assert(is_list(Msgs)),
  ?assertEqual(4, length(Msgs)),
  [M1, M2, M3, M4] = Msgs,
  ?assertEqual(<<"user">>, maps:get(<<"role">>, M1)),
  ?assertEqual(<<"hi">>, maps:get(<<"content">>, M1)),
  ?assertEqual(<<"assistant">>, maps:get(<<"role">>, M2)),
  ?assertEqual(<<>>, maps:get(<<"content">>, M2)),
  ToolCalls = maps:get(<<"tool_calls">>, M2, []),
  ?assertEqual(1, length(ToolCalls)),
  Tc = hd(ToolCalls),
  ?assertEqual(<<"c1">>, maps:get(<<"id">>, Tc)),
  Fn = maps:get(<<"function">>, Tc),
  ?assertEqual(<<"Read">>, maps:get(<<"name">>, Fn)),
  ?assertEqual(<<"{\"file_path\":\"x\"}">>, maps:get(<<"arguments">>, Fn)),
  ?assertEqual(<<"tool">>, maps:get(<<"role">>, M3)),
  ?assertEqual(<<"c1">>, maps:get(<<"tool_call_id">>, M3)),
  ?assertEqual(<<"\"ok\"">>, maps:get(<<"content">>, M3)),
  ?assertEqual(<<"assistant">>, maps:get(<<"role">>, M4)),
  ?assertEqual(<<"done">>, maps:get(<<"content">>, M4)),
  ok.

responses_tools_to_chat_tools_wraps_function_schema_test() ->
  Tools0 = [
    #{type => <<"function">>, name => <<"Read">>, description => <<"desc">>, parameters => #{type => <<"object">>, properties => #{}}}
  ],
  Tools = openagentic_openai_chat_completions:responses_tools_to_chat_tools_for_test(Tools0),
  ?assertEqual(1, length(Tools)),
  T = hd(Tools),
  ?assertEqual(<<"function">>, maps:get(<<"type">>, T)),
  Fn = maps:get(<<"function">>, T),
  ?assertEqual(<<"Read">>, maps:get(<<"name">>, Fn)),
  ?assertEqual(<<"desc">>, maps:get(<<"description">>, Fn)),
  ok.

parse_chat_response_extracts_tool_calls_test() ->
  ArgStr = <<"{\"file_path\":\"x\"}">>,
  Root =
    #{
      <<"id">> => <<"id1">>,
      <<"usage">> => #{<<"total_tokens">> => 1},
      <<"choices">> => [
        #{
          <<"message">> =>
            #{
              <<"content">> => <<"hello">>,
              <<"tool_calls">> => [
                #{
                  <<"id">> => <<"c1">>,
                  <<"type">> => <<"function">>,
                  <<"function">> => #{<<"name">> => <<"Read">>, <<"arguments">> => ArgStr}
                }
              ]
            }
        }
      ]
    },
  Body = openagentic_json:encode(Root),
  {ok, Out} = openagentic_openai_chat_completions:parse_chat_response_for_test(Body),
  ?assertEqual(<<"hello">>, maps:get(assistant_text, Out)),
  ?assertEqual(<<"id1">>, maps:get(response_id, Out)),
  ToolCalls = maps:get(tool_calls, Out, []),
  ?assertEqual(1, length(ToolCalls)),
  Tc = hd(ToolCalls),
  ?assertEqual(<<"c1">>, maps:get(tool_use_id, Tc)),
  ?assertEqual(<<"Read">>, maps:get(name, Tc)),
  Args = maps:get(arguments, Tc, #{}),
  ?assertEqual(<<"x">>, maps:get(<<"file_path">>, Args)),
  ok.
