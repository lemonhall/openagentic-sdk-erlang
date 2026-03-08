-module(openagentic_workflow_engine_test_workflows_b).

-export([write_workflow_provider_retry/2, write_workflow_decision_route/1]).

write_workflow_provider_retry(Root, EnableRetry) ->
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "draft.md"]), <<"# draft prompt\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "aggregate.md"]), <<"# aggregate prompt\n">>),
  AggregateStep0 =
    #{
      id => <<"aggregate">>,
      role => <<"shangshu">>,
      input => #{type => <<"step_output">>, step_id => <<"draft">>},
      prompt => #{type => <<"file">>, path => <<"workflows/prompts/aggregate.md">>},
      output_contract => #{type => <<"markdown_sections">>, required => [<<"Summary">>]},
      guards => [],
      on_pass => null,
      on_fail => null,
      max_attempts => 1
    },
  AggregateStep =
    case EnableRetry of
      true ->
        AggregateStep0#{retry_policy => #{transient_provider_errors => true, max_retries => 2, backoff_ms => 1}};
      false ->
        AggregateStep0
    end,
  Json =
    openagentic_json:encode(
      #{
        workflow_version => <<"1.0">>,
        name => <<"provider_retry">>,
        steps => [
          #{
            id => <<"draft">>,
            role => <<"zhongshu">>,
            input => #{type => <<"controller_input">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/draft.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Draft">>]},
            guards => [],
            on_pass => <<"aggregate">>,
            on_fail => null,
            max_attempts => 1
          },
          AggregateStep
        ]
      }
    ),
  openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "w_provider_retry.json"]), <<Json/binary, "\n">>).

write_workflow_decision_route(Root) ->
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "a.md"]), <<"# prompt a\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "b.md"]), <<"# prompt b\n">>),
  ok = openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "prompts", "c.md"]), <<"# prompt c\n">>),
  Json =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[",
      "{",
      "\"id\":\"a\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/a.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":\"b\",",
      "\"on_fail\":null",
      "},",
      "{",
      "\"id\":\"b\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"a\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/b.md\"},",
      "\"output_contract\":{\"type\":\"decision\",\"allowed\":[\"approve\",\"reject\"],\"format\":\"json\",\"fields\":[\"decision\",\"reasons\",\"required_changes\"]},",
      "\"guards\":[{\"type\":\"decision_requires_reasons\",\"when\":\"reject\"}],",
      "\"on_decision\":{\"approve\":\"c\",\"reject\":\"a\"},",
      "\"on_pass\":\"c\",",
      "\"on_fail\":null,",
      "\"max_attempts\":1",
      "},",
      "{",
      "\"id\":\"c\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"b\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/c.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"C\"]},",
      "\"guards\":[],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}",
      "]}">>,
  openagentic_workflow_engine_test_utils:write_file(filename:join([Root, "workflows", "w_decision.json"]), Json).

