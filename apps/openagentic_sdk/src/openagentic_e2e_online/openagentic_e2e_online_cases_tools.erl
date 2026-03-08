-module(openagentic_e2e_online_cases_tools).
-export([cases/2]).

cases(Cfg, TmpProject) ->
  [
    case_skill_responses_best_effort(Cfg, TmpProject),
    case_skill_tool(Cfg, TmpProject),
    case_slash_command_responses_tool(Cfg, TmpProject),
    case_slash_command_tool(Cfg, TmpProject)
  ].

case_skill_tool(Cfg, TmpProject) ->
  MarkerLine = openagentic_e2e_online_fixtures:expected_skill_marker_line(Cfg),
  ToolMods = [openagentic_tool_skill],
  Prompt =
    <<
      "Automated test. Use the Skill tool to load the skill named 'e2e-skill'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the skill (starts with MARKER=)\n"
      "- Line 2: SKILL_OK\n"
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
        allowed_tools => [<<"Skill">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(skill_ok, Res, <<"SKILL_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(skill_marker, Res, MarkerLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"Skill">>])
  ]).

case_skill_responses_best_effort(Cfg, TmpProject) ->
  MarkerLine = openagentic_e2e_online_fixtures:expected_skill_marker_line(Cfg),
  ToolMods = [openagentic_tool_skill],
  Prompt =
    <<
      "Automated test. Use the Skill tool to load the skill named 'e2e-skill'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the skill (starts with MARKER=)\n"
      "- Line 2: SKILL_R_OK\n"
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
        allowed_tools => [<<"Skill">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(skill_r_ok, Res, <<"SKILL_R_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(skill_r_marker, Res, MarkerLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"Skill">>])
  ]).

case_slash_command_responses_tool(Cfg, TmpProject) ->
  MarkerLine = openagentic_e2e_online_fixtures:expected_slash_command_marker_line(Cfg),
  ToolMods = [openagentic_tool_slash_command],
  Prompt =
    <<
      "Automated test. Use the SlashCommand tool to load command template named 'e2e'.\n"
      "Pass args: 'abc'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the rendered command output (starts with MARKER=)\n"
      "- Line 2: CMD_R_OK\n"
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
        allowed_tools => [<<"SlashCommand">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(cmd_r_ok, Res, <<"CMD_R_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(cmd_r_marker, Res, MarkerLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"SlashCommand">>])
  ]).

case_slash_command_tool(Cfg, TmpProject) ->
  MarkerLine = openagentic_e2e_online_fixtures:expected_slash_command_marker_line(Cfg),
  ToolMods = [openagentic_tool_slash_command],
  Prompt =
    <<
      "Automated test. Use the SlashCommand tool to load command template named 'e2e'.\n"
      "Pass args: 'abc'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the rendered command output (starts with MARKER=)\n"
      "- Line 2: CMD_OK\n"
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
        allowed_tools => [<<"SlashCommand">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(cmd_ok, Res, <<"CMD_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(cmd_marker, Res, MarkerLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"SlashCommand">>])
  ]).
