-module(openagentic_fs_tools_list_write_test).

-include_lib("eunit/include/eunit.hrl").

list_lists_files_and_ignores_common_dirs_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
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
  case binary:match(Output, <<"src/">>) of
    nomatch -> erlang:error({missing_src_dir_in_output, ProjectDir, Out});
    _ -> ok
  end,
  ?assert(binary:match(Output, <<"a.erl">>) =/= nomatch),
  ?assert(binary:match(Output, <<".git">>) =:= nomatch),
  ?assert(binary:match(Output, <<"node_modules">>) =:= nomatch).

list_truncates_when_limit_exceeded_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
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
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),
  Path = filename:join([WorkspaceDir, "w.txt"]),
  ok = file:write_file(Path, <<"old">>),

  {error, {kotlin_error, <<"IllegalStateException">>, Msg}} =
    openagentic_tool_write:run(#{file_path => <<"w.txt">>, content => <<"new">>}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assert(binary:match(Msg, <<"Write: file exists:">>) =/= nomatch),

  {ok, Out} =
    openagentic_tool_write:run(
      #{file_path => <<"w.txt">>, content => <<"new">>, overwrite => true},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),
  ?assertEqual(3, maps:get(bytes_written, Out)),
  ok.

write_and_read_support_workspace_prefix_and_block_project_write_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),

  {ok, _} =
    openagentic_tool_write:run(
      #{file_path => <<"deliverables/out.txt">>, content => <<"hello">>, overwrite => true},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),

  {ok, Out} =
    openagentic_tool_read:run(
      #{file_path => <<"workspace:deliverables/out.txt">>},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),
  ?assert(binary:match(maps:get(content, Out), <<"hello">>) =/= nomatch),

  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_write:run(
      #{file_path => <<"project:should_not_write.txt">>, content => <<"x">>, overwrite => true},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),
  ?assert(binary:match(Msg, <<"workspace root">>) =/= nomatch),
  ok.

list_not_found_is_illegal_argument_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_list:run(#{path => <<"missing-dir">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"List: not found:">>) =/= nomatch),
  ok.
