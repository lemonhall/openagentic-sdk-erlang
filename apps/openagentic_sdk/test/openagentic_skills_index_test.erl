-module(openagentic_skills_index_test).

-include_lib("eunit/include/eunit.hrl").

indexes_claude_skills_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj"]),
  SkillDir = filename:join([ProjectDir, ".claude", "skills", "a"]),
  ok = filelib:ensure_dir(filename:join([SkillDir, "x"])),
  ok = file:write_file(filename:join([SkillDir, "SKILL.md"]), <<"# a\n\nsummary\n">>),

  AgentsHome = filename:join([Root, "agents"]),
  GlobalHome = filename:join([Root, "home"]),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),
    Infos = openagentic_skills:index(ProjectDir),
    Names = [maps:get(name, I) || I <- Infos],
    ?assert(lists:member(<<"a">>, Names))
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

includes_global_skills_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj2"]),
  GlobalHome = filename:join([Root, "home"]),
  AgentsHome = filename:join([Root, "agents"]),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),
    G = filename:join([GlobalHome, "skills", "g"]),
    ok = filelib:ensure_dir(filename:join([G, "x"])),
    ok = file:write_file(
      filename:join([G, "SKILL.md"]),
      <<"---\nname: global-one\ndescription: gd\n---\n\n# global-one\n">>
    ),
    Infos = openagentic_skills:index(ProjectDir),
    Names = [maps:get(name, I) || I <- Infos],
    ?assert(lists:member(<<"global-one">>, Names))
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

project_overrides_global_on_name_collision_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj3"]),
  GlobalHome = filename:join([Root, "home2"]),
  AgentsHome = filename:join([Root, "agents"]),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),
    G = filename:join([GlobalHome, "skills", "a"]),
    ok = filelib:ensure_dir(filename:join([G, "x"])),
    ok = file:write_file(filename:join([G, "SKILL.md"]), <<"---\nname: a\ndescription: global\n---\n\n# A\n">>),

    P = filename:join([ProjectDir, ".claude", "skills", "a"]),
    ok = filelib:ensure_dir(filename:join([P, "x"])),
    ok = file:write_file(filename:join([P, "SKILL.md"]), <<"---\nname: a\ndescription: project\n---\n\n# A\n">>),

    Infos = openagentic_skills:index(ProjectDir),
    A = hd([I || I <- Infos, maps:get(name, I) =:= <<"a">>]),
    ?assertEqual(<<"project">>, maps:get(description, A))
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.


skill_root_skips_helper_subtrees_but_keeps_nested_skill_dirs_test() ->
  Root = test_root(),
  ProjectDir = filename:join([Root, "proj4"]),
  AgentsHome = filename:join([Root, "agents4"]),
  GlobalHome = filename:join([Root, "home4"]),
  ok = filelib:ensure_dir(filename:join([AgentsHome, "x"])),
  ok = filelib:ensure_dir(filename:join([GlobalHome, "x"])),

  OldAgents = os:getenv("OPENAGENTIC_AGENTS_HOME"),
  OldSdk = os:getenv("OPENAGENTIC_SDK_HOME"),
  try
    true = os:putenv("OPENAGENTIC_AGENTS_HOME", AgentsHome),
    true = os:putenv("OPENAGENTIC_SDK_HOME", GlobalHome),

    Outer = filename:join([ProjectDir, ".claude", "skills", "outer"]),
    Nested = filename:join([Outer, "nested"]),
    Helper = filename:join([Outer, "scripts", "helper"]),
    ok = filelib:ensure_dir(filename:join([Nested, "x"])),
    ok = filelib:ensure_dir(filename:join([Helper, "x"])),
    ok = file:write_file(filename:join([Outer, "SKILL.md"]), <<"---\nname: outer\ndescription: outer\n---\n\n# Outer\n">>),
    ok = file:write_file(filename:join([Nested, "SKILL.md"]), <<"---\nname: nested\ndescription: nested\n---\n\n# Nested\n">>),
    ok = file:write_file(filename:join([Helper, "SKILL.md"]), <<"---\nname: helper\ndescription: helper\n---\n\n# Helper\n">>),

    Infos = openagentic_skills:index(ProjectDir),
    Names = [maps:get(name, I) || I <- Infos],
    ?assert(lists:member(<<"outer">>, Names)),
    ?assert(lists:member(<<"nested">>, Names)),
    ?assertNot(lists:member(<<"helper">>, Names))
  after
    restore_env("OPENAGENTIC_AGENTS_HOME", OldAgents),
    restore_env("OPENAGENTIC_SDK_HOME", OldSdk)
  end.

restore_env(Name, false) ->
  os:unsetenv(Name);
restore_env(Name, Val) ->
  os:putenv(Name, Val).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_skills_index_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
