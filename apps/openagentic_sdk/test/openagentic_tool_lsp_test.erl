-module(openagentic_tool_lsp_test).

-include_lib("eunit/include/eunit.hrl").

requires_operation_test() ->
  ?assertEqual({error, {invalid_input, <<"lsp: 'operation' must be a non-empty string">>}}, openagentic_tool_lsp:run(#{}, #{})),
  ok.

requires_file_path_test() ->
  ?assertEqual({error, {invalid_input, <<"lsp: 'filePath' must be a non-empty string">>}}, openagentic_tool_lsp:run(#{operation => <<"hover">>}, #{})),
  ok.

disabled_by_config_test() ->
  Root = test_root(),
  FilePath = filename:join([Root, "src", "demo.erl"]),
  ok = filelib:ensure_dir(FilePath),
  ok = file:write_file(FilePath, <<"-module(demo).\n">>),
  ok = file:write_file(filename:join([Root, "opencode.json"]), openagentic_json:encode(#{lsp => false})),
  ?assertEqual(
    {error, {runtime_error, <<"lsp: disabled by config">>}},
    openagentic_tool_lsp:run(#{operation => <<"hover">>, filePath => <<"src/demo.erl">>, line => 1, character => 1}, #{project_dir => Root})
  ),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_tool_lsp_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
