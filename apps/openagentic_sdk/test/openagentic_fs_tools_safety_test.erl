-module(openagentic_fs_tools_safety_test).

-include_lib("eunit/include/eunit.hrl").

resolve_tool_path_blocks_symlink_escape_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  Outside = openagentic_fs_tools_test_support:test_root(),

  OutsideFile = filename:join([Outside, "outside.txt"]),
  ok = file:write_file(OutsideFile, <<"x">>),

  LinkPath = filename:join([ProjectDir, "link"]),
  case file:make_symlink(OutsideFile, LinkPath) of
    ok ->
      %% "link" exists, but points outside project root: "link/evil.txt" must be rejected.
      Res = openagentic_fs:resolve_tool_path(ProjectDir, filename:join(["link", "evil.txt"])),
      ?assertMatch({error, {kotlin_error, <<"IllegalArgumentException">>, _}}, Res),
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} = Res,
      ?assert(binary:match(Msg, <<"Tool path escapes project root via symlink:">>) =/= nomatch),
      ok;
    {error, _Reason} ->
      %% Some Windows setups require elevated permissions or Developer Mode for symlinks.
      ok
  end.

read_blocks_dotenv_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),
  ok = file:write_file(filename:join([ProjectDir, ".env"]), <<"SECRET=1\n">>),
  ok = file:write_file(filename:join([WorkspaceDir, ".env"]), <<"SECRET=2\n">>),

  {error, {kotlin_error, <<"RuntimeException">>, Msg1}} =
    openagentic_tool_read:run(#{file_path => <<".env">>}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assert(binary:match(Msg1, <<"access denied">>) =/= nomatch),

  {error, {kotlin_error, <<"RuntimeException">>, Msg2}} =
    openagentic_tool_read:run(#{file_path => <<"workspace:.env">>}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assert(binary:match(Msg2, <<"access denied">>) =/= nomatch),
  ok.
