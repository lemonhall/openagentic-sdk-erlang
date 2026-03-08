-module(openagentic_fs_tools_edit_test).

-include_lib("eunit/include/eunit.hrl").

edit_applies_replace_and_reports_missing_old_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),
  Path = filename:join([WorkspaceDir, "e.txt"]),
  ok = file:write_file(Path, <<"hello\n">>),

  {ok, Out1} =
    openagentic_tool_edit:run(
      #{file_path => <<"e.txt">>, old => <<"hello">>, new => <<"hi">>},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),
  ?assertEqual(<<"Edit applied">>, maps:get(message, Out1)),
  ?assertEqual(1, maps:get(replacements, Out1)),

  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' text not found in file">>}} =
    openagentic_tool_edit:run(
      #{file_path => <<"e.txt">>, old => <<"does-not-exist">>, new => <<"x">>},
      #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}
    ),
  ok.

edit_missing_file_is_file_not_found_exception_test() ->
  Root = openagentic_fs_tools_test_support:test_root(),
  ProjectDir = Root,
  WorkspaceDir = filename:join([Root, "ws"]),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir, "x"])),
  {error, {kotlin_error, <<"FileNotFoundException">>, Msg}} =
    openagentic_tool_edit:run(#{file_path => <<"missing.txt">>, old => <<"a">>, new => <<"b">>}, #{project_dir => ProjectDir, workspace_dir => WorkspaceDir}),
  ?assert(binary:match(Msg, <<"Edit: not found:">>) =/= nomatch),
  ok.
