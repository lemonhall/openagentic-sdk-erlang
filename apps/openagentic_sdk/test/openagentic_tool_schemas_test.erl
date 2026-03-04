-module(openagentic_tool_schemas_test).

-include_lib("eunit/include/eunit.hrl").

skill_schema_includes_available_skills_in_description_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj"]),
  SkillDir = filename:join([ProjectDir, ".claude", "skills", "foo"]),
  ok = filelib:ensure_dir(filename:join([SkillDir, "x"])),
  ok = file:write_file(
    filename:join([SkillDir, "SKILL.md"]),
    <<
      "---\n",
      "name: foo\n",
      "description: Foo skill\n",
      "---\n",
      "\n",
      "# Foo\n"
    >>
  ),

  AgentsHome = filename:join([Root, "agents"]),
  GlobalHome = filename:join([Root, "home"]),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),
    ToolMods = [openagentic_tool_skill],
    [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
    Desc = maps:get(description, Schema),
    ?assert(is_binary(Desc)),
    ?assert(binary:match(Desc, <<"<available_skills>">>) =/= nomatch),
    ?assert(binary:match(Desc, <<"foo">>) =/= nomatch),
    ?assert(binary:match(Desc, <<"Usage:">>) =/= nomatch)
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

restore_env(Name, false) ->
  os:unsetenv(Name);
restore_env(Name, Val) ->
  os:putenv(Name, Val).

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

slash_command_schema_includes_available_commands_in_description_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj_cmd"]),
  CmdDir = filename:join([ProjectDir, ".claude", "commands"]),
  ok = filelib:ensure_dir(filename:join([CmdDir, "x"])),
  ok = file:write_file(filename:join([CmdDir, "hello.md"]), <<"Hi ${args} at ${path}">>),

  AgentsHome = filename:join([Root, "agents2"]),
  GlobalHome = filename:join([Root, "home2"]),
  OpencodeDir = filename:join([Root, "opencode2"]),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),
  ok = filelib:ensure_dir(filename:join([OpencodeDir, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  OldOpencode = os:getenv("OPENCODE_CONFIG_DIR"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),
    true = os:putenv("OPENCODE_CONFIG_DIR", OpencodeDir),
  ToolMods = [openagentic_tool_slash_command],
  [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
  Desc = maps:get(description, Schema),
  ?assert(is_binary(Desc)),
  %% Kotlin parity: SlashCommand has no toolprompt resource; keep the built-in description only.
  ?assert(binary:match(Desc, <<"slash command">>) =/= nomatch)
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk),
    restore_env("OPENCODE_CONFIG_DIR", OldOpencode)
  end.

read_schema_includes_project_context_prompt_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj_read"]),
  ok = filelib:ensure_dir(filename:join([ProjectDir, "x"])),

  ToolMods = [openagentic_tool_read],
  [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
  Desc = maps:get(description, Schema),
  ?assert(binary:match(Desc, <<"Project root">>) =/= nomatch),
  NormProject = iolist_to_binary(string:replace(filename:absname(ProjectDir), "\\", "/", all)),
  ?assert(binary:match(Desc, NormProject) =/= nomatch),
  ?assert(binary:match(Desc, <<"file_path">>) =/= nomatch).

glob_schema_includes_project_context_prompt_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj_glob"]),
  ok = filelib:ensure_dir(filename:join([ProjectDir, "x"])),

  ToolMods = [openagentic_tool_glob],
  [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
  Desc = maps:get(description, Schema),
  ?assert(binary:match(Desc, <<"Project root">>) =/= nomatch),
  NormProject = iolist_to_binary(string:replace(filename:absname(ProjectDir), "\\", "/", all)),
  ?assert(binary:match(Desc, NormProject) =/= nomatch),
  ?assert(binary:match(Desc, <<"pattern">>) =/= nomatch).

grep_schema_includes_project_context_prompt_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj_grep"]),
  ok = filelib:ensure_dir(filename:join([ProjectDir, "x"])),

  ToolMods = [openagentic_tool_grep],
  [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
  Desc = maps:get(description, Schema),
  ?assert(binary:match(Desc, <<"regular expression">>) =/= nomatch),
  NormProject = iolist_to_binary(string:replace(filename:absname(ProjectDir), "\\", "/", all)),
  ?assert(binary:match(Desc, NormProject) =/= nomatch),
  ?assert(binary:match(Desc, <<"file_glob">>) =/= nomatch).

list_schema_includes_project_context_prompt_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj_list"]),
  ok = filelib:ensure_dir(filename:join([ProjectDir, "x"])),

  ToolMods = [openagentic_tool_list],
  [Schema] = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir}),
  Desc = maps:get(description, Schema),
  ?assert(binary:match(Desc, <<"Project root">>) =/= nomatch),
  NormProject = iolist_to_binary(string:replace(filename:absname(ProjectDir), "\\", "/", all)),
  ?assert(binary:match(Desc, NormProject) =/= nomatch),
  ?assert(binary:match(Desc, <<"path">>) =/= nomatch).
