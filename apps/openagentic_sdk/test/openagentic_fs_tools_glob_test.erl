-module(openagentic_fs_tools_glob_test).

-include_lib("eunit/include/eunit.hrl").

glob_blocks_unsafe_pattern_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "x.erl"]), <<"ok.">>),
  {ok, Out} = openagentic_tool_glob:run(#{pattern => <<"*.erl">>}, #{project_dir => ProjectDir}),
  Matches = maps:get(matches, Out),
  ?assert(length(Matches) >= 1),
  {ok, Out2} = openagentic_tool_glob:run(#{pattern => <<"C:\\\\Windows\\\\*.exe">>}, #{project_dir => ProjectDir}),
  ?assertEqual([], maps:get(matches, Out2)).

glob_supports_starstar_recursive_patterns_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  Src = filename:join([ProjectDir, "src"]),
  Sub = filename:join([Src, "sub"]),
  ok = filelib:ensure_dir(filename:join([Sub, "x"])),
  ok = file:write_file(filename:join([Src, "a.erl"]), <<"ok.">>),
  ok = file:write_file(filename:join([Sub, "b.erl"]), <<"ok.">>),

  {ok, Out1} = openagentic_tool_glob:run(#{pattern => <<"**/*.erl">>}, #{project_dir => ProjectDir}),
  Matches1 = maps:get(matches, Out1),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches1, <<"src/a.erl">>)),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches1, <<"src/sub/b.erl">>)),

  {ok, Out2} = openagentic_tool_glob:run(#{pattern => <<"src/**/*.erl">>}, #{project_dir => ProjectDir}),
  Matches2 = maps:get(matches, Out2),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches2, <<"src/a.erl">>)),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches2, <<"src/sub/b.erl">>)).

glob_reports_count_and_truncation_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "a.txt"]), <<"x">>),
  ok = file:write_file(filename:join([ProjectDir, "b.txt"]), <<"x">>),
  ok = file:write_file(filename:join([ProjectDir, "c.txt"]), <<"x">>),

  {ok, Out} =
    openagentic_tool_glob:run(
      #{pattern => <<"**/*.txt">>},
      #{project_dir => ProjectDir}
    ),
  ?assertEqual(false, maps:get(truncated, Out)),
  ?assert(maps:get(count, Out) >= 3),
  Matches = maps:get(matches, Out),
  ?assert(length(Matches) >= 3),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches, <<"a.txt">>)),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches, <<"b.txt">>)),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches, <<"c.txt">>)),
  ?assert(is_binary(maps:get(root, Out))).

glob_respects_root_base_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = filelib:ensure_dir(filename:join([ProjectDir, "src", "x"])),
  ok = file:write_file(filename:join([ProjectDir, "src", "a.erl"]), <<"ok.">>),
  ok = file:write_file(filename:join([ProjectDir, "other.erl"]), <<"ok.">>),

  {ok, Out} =
    openagentic_tool_glob:run(
      #{pattern => <<"**/*.erl">>, root => <<"src">>},
      #{project_dir => ProjectDir}
    ),
  Matches = maps:get(matches, Out),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches, <<"src/a.erl">>)),
  ?assert(not openagentic_fs_tools_test_support:has_subpath(Matches, <<"other.erl">>)).
