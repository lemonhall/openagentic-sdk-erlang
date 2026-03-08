-module(openagentic_workflow_engine_test_workflows_c).

-export([write_workflow_fanout/1]).

write_workflow_fanout(Root) ->
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "dispatch.md"]), <<"# dispatch\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "hubu.md"]), <<"只允许写入 workspace:staging/hubu/poem.md\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "gongbu.md"]), <<"只允许写入 workspace:staging/gongbu/poem.md\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "aggregate.md"]), <<"# aggregate\n">>),
  Json =
    openagentic_json:encode(
      #{
        workflow_version => <<"1.0">>,
        name => <<"fanout">>,
        steps => [
          #{
            id => <<"dispatch">>,
            role => <<"shangshu">>,
            input => #{type => <<"controller_input">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/dispatch.md">>},
            output_contract => #{type => <<"json_object">>, schema_hint => #{tasks => []}},
            guards => [#{type => <<"regex_must_match">>, pattern => <<"tasks">>}],
            on_pass => <<"fanout">>,
            on_fail => null
          },
          #{
            id => <<"fanout">>,
            role => <<"shangshu">>,
            executor => <<"fanout_join">>,
            fanout => #{steps => [<<"hubu">>, <<"gongbu">>], join => <<"aggregate">>, max_concurrency => 2, fail_fast => false},
            on_fail => null
          },
          #{
            id => <<"hubu">>,
            role => <<"hubu">>,
            input => #{type => <<"step_output">>, step_id => <<"dispatch">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/hubu.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Result">>, <<"Artifacts">>, <<"Handoff">>]},
            guards => [],
            on_pass => null,
            on_fail => <<"hubu">>,
            max_attempts => 2
          },
          #{
            id => <<"gongbu">>,
            role => <<"gongbu">>,
            input => #{type => <<"step_output">>, step_id => <<"dispatch">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/gongbu.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Result">>, <<"Artifacts">>, <<"Handoff">>]},
            guards => [],
            on_pass => null,
            on_fail => <<"gongbu">>,
            max_attempts => 2
          },
          #{
            id => <<"aggregate">>,
            role => <<"shangshu">>,
            input => #{type => <<"merge">>, sources => [#{type => <<"step_output">>, step_id => <<"hubu">>}, #{type => <<"step_output">>, step_id => <<"gongbu">>}]},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/aggregate.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Summary">>]},
            guards => [],
            on_pass => null,
            on_fail => null
          }
        ]
      }
    ),
  openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "w_fanout.json"]), <<Json/binary, "\n">>).
