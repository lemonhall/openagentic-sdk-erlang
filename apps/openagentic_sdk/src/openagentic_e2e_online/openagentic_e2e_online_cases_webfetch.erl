-module(openagentic_e2e_online_cases_webfetch).
-export([cases/2]).

cases(Cfg, TmpProject) ->
  [
    case_webfetch_responses_tool(Cfg, TmpProject),
    case_webfetch_tool(Cfg, TmpProject)
  ].

case_webfetch_responses_tool(Cfg, TmpProject) ->
  ToolMods = [openagentic_tool_webfetch],
  Prompt =
    <<
      "Automated test. Use WebFetch tool to fetch https://example.com/ with mode 'text'.\n"
      "Then reply only: WEB_R_OK\n"
    >>,
  Opts =
    openagentic_e2e_online_query:base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"WebFetch">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(web_r_ok, Res, <<"WEB_R_OK">>),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"WebFetch">>])
  ]).

case_webfetch_tool(Cfg, TmpProject) ->
  ToolMods = [openagentic_tool_webfetch],
  Prompt =
    <<
      "Automated test. Use WebFetch tool to fetch https://example.com/ with mode 'text'.\n"
      "Then reply only: WEB_OK\n"
    >>,
  Opts =
    openagentic_e2e_online_query:base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"WebFetch">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(web_ok, Res, <<"WEB_OK">>),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"WebFetch">>])
  ]).
