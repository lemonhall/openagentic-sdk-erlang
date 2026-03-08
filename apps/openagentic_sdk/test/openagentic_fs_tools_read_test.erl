-module(openagentic_fs_tools_read_test).

-include_lib("eunit/include/eunit.hrl").

read_respects_offset_limit_and_blocks_traversal_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),
  ok = file:write_file(filename:join([ProjectDir, "a.txt"]), <<"l1\nl2\nl3\n">>),

  {ok, Out1} = openagentic_tool_read:run(#{file_path => <<"a.txt">>, offset => 2, limit => 1}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assertEqual(<<"2: l2">>, maps:get(content, Out1)),
  ?assertEqual(3, maps:get(total_lines, Out1)),
  ?assertEqual(1, maps:get(lines_returned, Out1)),

  {ok, AbsNative} = openagentic_fs:resolve_tool_path(ProjectDir, "a.txt"),
  Abs = iolist_to_binary(AbsNative),
  {ok, OutAbs} = openagentic_tool_read:run(#{file_path => Abs, offset => 1, limit => 1}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assertEqual(<<"1: l1">>, maps:get(content, OutAbs)),

  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_read:run(#{file_path => <<"../x.txt">>}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assert(binary:match(Msg, <<"Tool path must be under project root:">>) =/= nomatch).

read_reads_images_as_base64_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  Bytes = <<1, 2, 3, 4, 5>>,
  ok = file:write_file(filename:join([ProjectDir, "img.png"]), Bytes),
  {ok, Out} = openagentic_tool_read:run(#{file_path => <<"img.png">>}, #{project_dir => ProjectDir}),
  ?assertEqual(<<"image/png">>, maps:get(mime_type, Out)),
  ?assertEqual(base64:encode(Bytes), maps:get(image, Out)),
  ?assertEqual(false, maps:get(truncated, Out)).

read_missing_file_is_file_not_found_exception_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  {error, {kotlin_error, <<"FileNotFoundException">>, Msg}} =
    openagentic_tool_read:run(#{file_path => <<"missing.txt">>}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"Read: not found:">>) =/= nomatch).

read_offset_out_of_range_matches_kotlin_message_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  ok = file:write_file(filename:join([ProjectDir, "r.txt"]), <<"l1\nl2\n">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_read:run(#{file_path => <<"r.txt">>, offset => 3, limit => 1}, #{project_dir => ProjectDir}),
  ?assert(binary:match(Msg, <<"Read: 'offset' out of range:">>) =/= nomatch),
  ok.
