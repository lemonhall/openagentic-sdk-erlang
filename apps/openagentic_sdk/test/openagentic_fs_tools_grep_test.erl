-module(openagentic_fs_tools_grep_test).

-include_lib("eunit/include/eunit.hrl").

grep_finds_matches_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "g.txt"]), <<"hello\nworld\nhello\n">>),
  {ok, Out} = openagentic_tool_grep:run(#{query => <<"hello">>, file_glob => <<"**/*">>}, #{project_dir => ProjectDir}),
  Matches = maps:get(matches, Out),
  ?assert(length(Matches) >= 2),
  ?assertEqual(false, maps:get(truncated, Out)),
  ?assert(maps:get(total_matches, Out) >= 2).

grep_invalid_regex_uses_pattern_syntax_exception_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "g.txt"]), <<"hello\n">>),
  {error, {kotlin_error, <<"PatternSyntaxException">>, Msg}} =
    openagentic_tool_grep:run(#{query => <<"(">>, file_glob => <<"**/*">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"near index">>) =/= nomatch).

grep_respects_glob_filter_with_starstar_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  Src = filename:join([ProjectDir, "src"]),
  Sub = filename:join([Src, "sub"]),
  ok = filelib:ensure_dir(filename:join([Sub, "x"])),
  ok = file:write_file(filename:join([Src, "a.erl"]), <<"hello\n">>),
  ok = file:write_file(filename:join([Sub, "b.erl"]), <<"hello\n">>),
  ok = file:write_file(filename:join([ProjectDir, "other.txt"]), <<"hello\n">>),

  {ok, Out} =
    openagentic_tool_grep:run(
      #{query => <<"hello">>, file_glob => <<"src/**/*.erl">>},
      #{project_dir => ProjectDir}
    ),
  Matches = maps:get(matches, Out),
  %% must not match files outside src/**/*.erl
  ?assert(not openagentic_fs_tools_test_support:has_match_file(Matches, <<"other.txt">>)),
  ?assert(openagentic_fs_tools_test_support:has_match_file(Matches, <<"src/a.erl">>)),
  ?assert(openagentic_fs_tools_test_support:has_match_file(Matches, <<"src/sub/b.erl">>)).

grep_mode_files_with_matches_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "a.txt"]), <<"hello\n">>),
  ok = file:write_file(filename:join([ProjectDir, "b.txt"]), <<"x\nhello\n">>),

  {ok, Out} =
    openagentic_tool_grep:run(
      #{query => <<"hello">>, file_glob => <<"**/*">>, mode => <<"files_with_matches">>},
      #{project_dir => ProjectDir}
    ),
  Files = maps:get(files, Out),
  ?assert(is_list(Files)),
  ?assert(length(Files) >= 2),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Files, <<"a.txt">>)),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Files, <<"b.txt">>)).

grep_supports_context_and_case_insensitive_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok =
    file:write_file(
      filename:join([ProjectDir, "c.txt"]),
      <<"before\nhello\nafter\n">>
    ),

  {ok, Out} =
    openagentic_tool_grep:run(
      #{
        query => <<"HELLO">>,
        file_glob => <<"**/*">>,
        case_sensitive => false,
        before_context => 1,
        after_context => 1
      },
      #{project_dir => ProjectDir}
    ),
  Ms = maps:get(matches, Out),
  [M | _] =
    [
      X
      || X <- Ms,
         maps:get(line, X, 0) =:= 2,
         (binary:match(openagentic_fs_tools_test_support:norm(maps:get(file_path, X, <<>>)), <<"c.txt">>) =/= nomatch)
    ],
  ?assertEqual([<<"before">>], maps:get(before_context, M)),
  ?assertEqual([<<"after">>], maps:get(after_context, M)).

grep_excludes_hidden_when_include_hidden_false_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = filelib:ensure_dir(filename:join([ProjectDir, ".h", "x"])),
  ok = file:write_file(filename:join([ProjectDir, ".h", "hidden.txt"]), <<"hello\n">>),
  ok = file:write_file(filename:join([ProjectDir, "visible.txt"]), <<"hello\n">>),

  {ok, Out} =
    openagentic_tool_grep:run(
      #{query => <<"hello">>, file_glob => <<"**/*">>, include_hidden => false},
      #{project_dir => ProjectDir}
    ),
  Matches = maps:get(matches, Out),
  ?assert(not openagentic_fs_tools_test_support:has_match_file(Matches, <<"hidden.txt">>)),
  ?assert(openagentic_fs_tools_test_support:has_match_file(Matches, <<"visible.txt">>)).
