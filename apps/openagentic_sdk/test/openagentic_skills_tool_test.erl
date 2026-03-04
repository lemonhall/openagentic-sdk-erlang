-module(openagentic_skills_tool_test).

-include_lib("eunit/include/eunit.hrl").

skill_index_and_tool_lookup_test() ->
  Root = test_root(),
  %% Create a global agents root skill
  AgentsRoot = filename:join([Root, "agents"]),
  SkillDir1 = filename:join([AgentsRoot, "skills", "foo"]),
  ok = filelib:ensure_dir(filename:join([SkillDir1, "x"])),
  ok = file:write_file(
    filename:join([SkillDir1, "SKILL.md"]),
    <<
      "---\n",
      "name: foo\n",
      "description: Foo skill\n",
      "---\n",
      "# Foo\n",
      "Hello\n"
    >>
  ),
  GlobalHome = filename:join([Root, "global"]),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),

  %% Create a project-local overriding skill
  ProjectDir = filename:join([Root, "proj"]),
  SkillDir2 = filename:join([ProjectDir, "skills", "foo"]),
  ok = filelib:ensure_dir(filename:join([SkillDir2, "x"])),
  ok = file:write_file(
    filename:join([SkillDir2, "SKILL.md"]),
    <<
      "---\n",
      "name: foo\n",
      "description: Project Foo\n",
      "---\n",
      "# FooProj\n"
    >>
  ),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsRoot),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),

    Infos = openagentic_skills:index(ProjectDir),
    Found = [I || I <- Infos, maps:get(name, I) =:= <<"foo">>],
    ?assert(length(Found) =:= 1),
    [Info] = Found,
    ?assertEqual(<<"Project Foo">>, maps:get(description, Info)),

    {ok, Out} = openagentic_tool_skill:run(#{name => <<"foo">>}, #{project_dir => ProjectDir}),
    ?assertEqual(<<"foo">>, maps:get(name, Out)),
    ?assert(is_binary(maps:get(output, Out))),
    ?assert(is_map(maps:get(metadata, Out)))
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

skill_tool_parses_summary_and_checklist_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj2"]),
  SkillDir = filename:join([ProjectDir, "skills", "bar"]),
  ok = filelib:ensure_dir(filename:join([SkillDir, "x"])),
  ok = file:write_file(
    filename:join([SkillDir, "SKILL.md"]),
    <<
      "---\n",
      "name: bar\n",
      "description: Bar skill\n",
      "---\n",
      "\n",
      "# Bar\n",
      "\n",
      "This is summary line 1\n",
      "summary line 2\n",
      "\n",
      "## Checklist\n",
      "- one\n",
      "* two\n",
      "\n"
    >>
  ),

  AgentsHome = filename:join([Root, "agents2"]),
  GlobalHome = filename:join([Root, "global2"]),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),

    {ok, Out} = openagentic_tool_skill:run(#{name => <<"bar">>}, #{project_dir => ProjectDir}),
    ?assertEqual(<<"Bar skill">>, maps:get(description, Out)),
    ?assertEqual(<<"This is summary line 1\nsummary line 2">>, maps:get(summary, Out)),
    ?assertEqual([<<"one">>, <<"two">>], maps:get(checklist, Out)),
    ?assert(is_binary(maps:get(output, Out))),
    ?assert(binary:match(maps:get(output, Out), <<"Base directory">>) =/= nomatch)
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

slash_command_loads_and_renders_args_and_path_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj3"]),
  ok = filelib:ensure_dir(filename:join([ProjectDir, ".git", "x"])),
  CmdDir = filename:join([ProjectDir, ".claude", "commands"]),
  ok = filelib:ensure_dir(filename:join([CmdDir, "x"])),
  ok = file:write_file(
    filename:join([CmdDir, "hello.md"]),
    <<"Hi ${args} at ${path}">>
  ),

  {ok, Out} = openagentic_tool_slash_command:run(#{name => <<"hello">>, args => <<"there">>}, #{project_dir => ProjectDir}),
  Content = maps:get(content, Out),
  ?assert(binary:match(Content, <<"there">>) =/= nomatch),
  AbsProject = filename:absname(ProjectDir),
  NormProject = iolist_to_binary(string:replace(AbsProject, "\\", "/", all)),
  ?assert(binary:match(Content, NormProject) =/= nomatch).

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

restore_env(Name, false) ->
  os:unsetenv(Name);
restore_env(Name, Val) ->
  os:putenv(Name, Val).
