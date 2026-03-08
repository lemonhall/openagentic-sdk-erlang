-module(openagentic_tools_contract_path_guard_test).

-include_lib("eunit/include/eunit.hrl").

glob_root_missing_throws_file_not_found_exception_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  {error, {kotlin_error, <<"FileNotFoundException">>, Msg}} =
    openagentic_tool_glob:run(#{pattern => <<"**/*">>, root => <<"missing_dir">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Glob: not found:">>) =/= nomatch).

glob_root_not_directory_throws_illegal_argument_exception_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_glob:run(#{pattern => <<"**/*">>, root => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Glob: not a directory:">>) =/= nomatch).

grep_root_not_directory_throws_illegal_argument_exception_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_grep:run(#{query => <<"x">>, file_glob => <<"**/*">>, root => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Grep: not a directory:">>) =/= nomatch).

bash_workdir_not_directory_throws_illegal_argument_exception_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_bash:run(#{command => <<"echo hi">>, workdir => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Bash: not a directory:">>) =/= nomatch).

bash_requires_command_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Bash: 'command' must be a non-empty string">>}} =
    openagentic_tool_bash:run(#{command => <<"">>}, #{project_dir => "."}).
