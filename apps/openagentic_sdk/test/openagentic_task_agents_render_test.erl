-module(openagentic_task_agents_render_test).

-include_lib("eunit/include/eunit.hrl").

task_tool_description_renders_agents_list_test() ->
  Agents = [
    openagentic_built_in_subagents:explore_agent(),
    openagentic_built_in_subagents:research_agent(),
    #{name => <<"webview">>, description => <<"Drive an embedded WebView.">>, allowed_tools => [<<"web_*">>]}
  ],
  AgentsVar = openagentic_task_agents:render_agents_for_prompt(Agents),
  Ctx = #{project_dir => ".", directory => ".", agents => AgentsVar},
  [Schema] = openagentic_tool_schemas:responses_tools([openagentic_tool_task], Ctx),
  Desc = maps:get(description, Schema, <<>>),
  ?assert(binary:match(Desc, <<"- explore:">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"- research:">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"- webview:">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"{{agents}}">>) =:= nomatch),
  ?assert(binary:match(Desc, <<"{agents}">>) =:= nomatch),
  ?assert(binary:match(Desc, <<"Task(agent=\"explore\"">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"Task(agent=\"research\"">>) =/= nomatch),
  ok.
