-module(openagentic_fs_tools_test).

-include_lib("eunit/include/eunit.hrl").

read_respects_offset_limit_and_blocks_traversal_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "a.txt"]), <<"l1\nl2\nl3\n">>),

  {ok, Out1} = openagentic_tool_read:run(#{file_path => <<"a.txt">>, offset => 2, limit => 1}, #{project_dir => ProjectDir}),
  ?assertEqual(<<"2: l2">>, maps:get(content, Out1)),
  ?assertEqual(3, maps:get(total_lines, Out1)),
  ?assertEqual(1, maps:get(lines_returned, Out1)),

  {ok, AbsNative} = openagentic_fs:resolve_tool_path(ProjectDir, "a.txt"),
  Abs = iolist_to_binary(AbsNative),
  {ok, OutAbs} = openagentic_tool_read:run(#{file_path => Abs, offset => 1, limit => 1}, #{project_dir => ProjectDir}),
  ?assertEqual(<<"1: l1">>, maps:get(content, OutAbs)),

  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_read:run(#{file_path => <<"../x.txt">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"Tool path must be under project root:">>) =/= nomatch).

read_reads_images_as_base64_test() ->
  Root = test_root(),
  ProjectDir = Root,
  Bytes = <<1, 2, 3, 4, 5>>,
  ok = file:write_file(filename:join([ProjectDir, "img.png"]), Bytes),
  {ok, Out} = openagentic_tool_read:run(#{file_path => <<"img.png">>}, #{project_dir => ProjectDir}),
  ?assertEqual(<<"image/png">>, maps:get(mime_type, Out)),
  ?assertEqual(base64:encode(Bytes), maps:get(image, Out)),
  ?assertEqual(false, maps:get(truncated, Out)).

glob_blocks_unsafe_pattern_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "x.erl"]), <<"ok.">>),
  {ok, Out} = openagentic_tool_glob:run(#{pattern => <<"*.erl">>}, #{project_dir => ProjectDir}),
  Matches = maps:get(matches, Out),
  ?assert(length(Matches) >= 1),
  {ok, Out2} = openagentic_tool_glob:run(#{pattern => <<"C:\\\\Windows\\\\*.exe">>}, #{project_dir => ProjectDir}),
  ?assertEqual([], maps:get(matches, Out2)).

glob_supports_starstar_recursive_patterns_test() ->
  Root = test_root(),
  ProjectDir = Root,
  Src = filename:join([ProjectDir, "src"]),
  Sub = filename:join([Src, "sub"]),
  ok = filelib:ensure_dir(filename:join([Sub, "x"])),
  ok = file:write_file(filename:join([Src, "a.erl"]), <<"ok.">>),
  ok = file:write_file(filename:join([Sub, "b.erl"]), <<"ok.">>),

  {ok, Out1} = openagentic_tool_glob:run(#{pattern => <<"**/*.erl">>}, #{project_dir => ProjectDir}),
  Matches1 = maps:get(matches, Out1),
  ?assert(has_subpath(Matches1, <<"src/a.erl">>)),
  ?assert(has_subpath(Matches1, <<"src/sub/b.erl">>)),

  {ok, Out2} = openagentic_tool_glob:run(#{pattern => <<"src/**/*.erl">>}, #{project_dir => ProjectDir}),
  Matches2 = maps:get(matches, Out2),
  ?assert(has_subpath(Matches2, <<"src/a.erl">>)),
  ?assert(has_subpath(Matches2, <<"src/sub/b.erl">>)).

glob_reports_count_and_truncation_test() ->
  Root = test_root(),
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
  ?assert(has_subpath(Matches, <<"a.txt">>)),
  ?assert(has_subpath(Matches, <<"b.txt">>)),
  ?assert(has_subpath(Matches, <<"c.txt">>)),
  ?assert(is_binary(maps:get(root, Out))).

glob_respects_root_base_test() ->
  Root = test_root(),
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
  ?assert(has_subpath(Matches, <<"src/a.erl">>)),
  ?assert(not has_subpath(Matches, <<"other.erl">>)).

grep_finds_matches_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "g.txt"]), <<"hello\nworld\nhello\n">>),
  {ok, Out} = openagentic_tool_grep:run(#{query => <<"hello">>, file_glob => <<"**/*">>}, #{project_dir => ProjectDir}),
  Matches = maps:get(matches, Out),
  ?assert(length(Matches) >= 2),
  ?assertEqual(false, maps:get(truncated, Out)),
  ?assert(maps:get(total_matches, Out) >= 2).

grep_respects_glob_filter_with_starstar_test() ->
  Root = test_root(),
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
  ?assert(not has_match_file(Matches, <<"other.txt">>)),
  ?assert(has_match_file(Matches, <<"src/a.erl">>)),
  ?assert(has_match_file(Matches, <<"src/sub/b.erl">>)).

grep_mode_files_with_matches_test() ->
  Root = test_root(),
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
  ?assert(has_subpath(Files, <<"a.txt">>)),
  ?assert(has_subpath(Files, <<"b.txt">>)).

grep_supports_context_and_case_insensitive_test() ->
  Root = test_root(),
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
  [M | _] = [X || X <- Ms, maps:get(line, X, 0) =:= 2],
  ?assertEqual([<<"before">>], maps:get(before_context, M)),
  ?assertEqual([<<"after">>], maps:get(after_context, M)).

grep_excludes_hidden_when_include_hidden_false_test() ->
  Root = test_root(),
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
  ?assert(not has_match_file(Matches, <<"hidden.txt">>)),
  ?assert(has_match_file(Matches, <<"visible.txt">>)).

has_subpath(Files, Sub0) ->
  Sub = norm(Sub0),
  lists:any(fun(F) -> binary:match(norm(F), Sub) =/= nomatch end, Files).

has_match_file(Matches, Sub0) ->
  Sub = norm(Sub0),
  lists:any(
    fun(M) ->
      P = maps:get(file_path, M, <<>>),
      binary:match(norm(P), Sub) =/= nomatch
    end,
    Matches
  ).

norm(B) when is_binary(B) ->
  iolist_to_binary(string:replace(B, <<"\\">>, <<"/">>, all));
norm(L) when is_list(L) ->
  norm(iolist_to_binary(L));
norm(Other) ->
  norm(iolist_to_binary(io_lib:format("~p", [Other]))).

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

list_lists_files_and_ignores_common_dirs_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = filelib:ensure_dir(filename:join([ProjectDir, "src", "x"])),
  ok = filelib:ensure_dir(filename:join([ProjectDir, ".git", "x"])),
  ok = filelib:ensure_dir(filename:join([ProjectDir, "node_modules", "x"])),
  ok = file:write_file(filename:join([ProjectDir, "src", "a.erl"]), <<"ok.">>),
  ok = file:write_file(filename:join([ProjectDir, ".git", "config"]), <<"x">>),
  ok = file:write_file(filename:join([ProjectDir, "node_modules", "a.js"]), <<"x">>),

  {ok, Out} = openagentic_tool_list:run(#{path => <<"./">>}, #{project_dir => ProjectDir}),
  Output = maps:get(output, Out),
  ?assert(is_binary(Output)),
  ?assert(binary:match(Output, <<"src/">>) =/= nomatch),
  ?assert(binary:match(Output, <<"a.erl">>) =/= nomatch),
  ?assert(binary:match(Output, <<".git">>) =:= nomatch),
  ?assert(binary:match(Output, <<"node_modules">>) =:= nomatch).

list_truncates_when_limit_exceeded_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = filelib:ensure_dir(filename:join([ProjectDir, "d", "x"])),
  ok = lists:foreach(
    fun (I) ->
      Name = filename:join([ProjectDir, "d", lists:flatten(io_lib:format("f~3..0b.txt", [I]))]),
      ok = file:write_file(Name, <<"x">>)
    end,
    lists:seq(1, 101)
  ),

  {ok, Out} = openagentic_tool_list:run(#{path => <<"d">>}, #{project_dir => ProjectDir}),
  ?assertEqual(true, maps:get(truncated, Out)),
  ?assertEqual(100, maps:get(count, Out)).

write_requires_overwrite_when_file_exists_test() ->
  Root = test_root(),
  ProjectDir = Root,
  Path = filename:join([ProjectDir, "w.txt"]),
  ok = file:write_file(Path, <<"old">>),

  {error, {kotlin_error, <<"IllegalStateException">>, Msg}} =
    openagentic_tool_write:run(#{file_path => <<"w.txt">>, content => <<"new">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"Write: file exists:">>) =/= nomatch),

  {ok, Out} =
    openagentic_tool_write:run(
      #{file_path => <<"w.txt">>, content => <<"new">>, overwrite => true},
      #{project_dir => ProjectDir}
    ),
  ?assertEqual(3, maps:get(bytes_written, Out)),
  ok.

edit_applies_replace_and_reports_missing_old_test() ->
  Root = test_root(),
  ProjectDir = Root,
  Path = filename:join([ProjectDir, "e.txt"]),
  ok = file:write_file(Path, <<"hello\n">>),

  {ok, Out1} =
    openagentic_tool_edit:run(
      #{file_path => <<"e.txt">>, old => <<"hello">>, new => <<"hi">>},
      #{project_dir => ProjectDir}
    ),
  ?assertEqual(<<"Edit applied">>, maps:get(message, Out1)),
  ?assertEqual(1, maps:get(replacements, Out1)),

  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' text not found in file">>}} =
    openagentic_tool_edit:run(
      #{file_path => <<"e.txt">>, old => <<"does-not-exist">>, new => <<"x">>},
      #{project_dir => ProjectDir}
    ),
  ok.

list_not_found_is_illegal_argument_test() ->
  Root = test_root(),
  ProjectDir = Root,
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_list:run(#{path => <<"missing-dir">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"List: not found:">>) =/= nomatch),
  ok.

read_offset_out_of_range_matches_kotlin_message_test() ->
  Root = test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "r.txt"]), <<"l1\nl2\n">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_read:run(#{file_path => <<"r.txt">>, offset => 3, limit => 1}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"Read: 'offset' out of range:">>) =/= nomatch),
  ok.
