-module(openagentic_task_runners_test).

-include_lib("eunit/include/eunit.hrl").

compose_delegates_to_next_runner_test() ->
  Runner =
    openagentic_task_runners:compose([
      fun (_Agent, _Prompt, _Ctx) -> erlang:error({unhandled_agent, <<"explore">>}) end,
      fun (Agent, Prompt, Ctx) -> #{agent => Agent, prompt => Prompt, ctx => Ctx} end
    ]),
  ?assertEqual(#{agent => <<"explore">>, prompt => <<"hello">>, ctx => #{k => v}}, Runner(<<"explore">>, <<"hello">>, #{k => v})),
  ok.

built_in_explore_rejects_unknown_agent_test() ->
  Runner = openagentic_task_runners:built_in_explore(#{}),
  ?assertException(error, {unhandled_agent, <<"other">>}, Runner(<<"other">>, <<"hello">>, #{})),
  ok.

built_in_research_rejects_unknown_agent_test() ->
  Runner = openagentic_task_runners:built_in_research(#{}),
  ?assertException(error, {unhandled_agent, <<"other">>}, Runner(<<"other">>, <<"hello">>, #{})),
  ok.
