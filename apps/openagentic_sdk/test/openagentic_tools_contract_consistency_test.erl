-module(openagentic_tools_contract_consistency_test).

-include_lib("eunit/include/eunit.hrl").

glob_contract_schema_prompt_and_runtime_are_aligned_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  ok = file:write_file(filename:join([Root, "a.erl"]), <<"ok.
">>),
  [Schema] = openagentic_tool_schemas:responses_tools([openagentic_tool_glob], #{project_dir => Root}),
  Params = maps:get(parameters, Schema),
  Props = maps:get(properties, Params),
  Desc = maps:get(description, Schema),
  ?assert(maps:is_key(pattern, Props)),
  ?assert(maps:is_key(root, Props)),
  ?assert(maps:is_key(path, Props)),
  ?assert(binary:match(Desc, <<"`pattern`">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"`root` (or `path`)">>) =/= nomatch),
  {ok, Out} = openagentic_tool_glob:run(#{pattern => <<"**/*.erl">>, path => <<".">>}, #{project_dir => Root}),
  Matches = maps:get(matches, Out),
  ?assert(openagentic_fs_tools_test_support:has_subpath(Matches, <<"a.erl">>)),
  ok.

grep_contract_schema_prompt_and_runtime_are_aligned_test() ->
  Root = openagentic_tools_contract_test_support:test_root(),
  ok = file:write_file(filename:join([Root, "g.txt"]), <<"hello
world
">>),
  [Schema] = openagentic_tool_schemas:responses_tools([openagentic_tool_grep], #{project_dir => Root}),
  Params = maps:get(parameters, Schema),
  Props = maps:get(properties, Params),
  Desc = maps:get(description, Schema),
  ?assert(maps:is_key(query, Props)),
  ?assert(maps:is_key(file_glob, Props)),
  ?assert(maps:is_key(root, Props)),
  ?assert(maps:is_key(path, Props)),
  ?assert(maps:is_key(mode, Props)),
  ?assert(binary:match(Desc, <<"`query`">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"`file_glob`">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"`root` (or `path`)">>) =/= nomatch),
  ?assert(binary:match(Desc, <<"mode=\"files_with_matches\"">>) =/= nomatch),
  {ok, Out} =
    openagentic_tool_grep:run(
      #{query => <<"hello">>, file_glob => <<"**/*">>, path => <<".">>, mode => <<"files_with_matches">>},
      #{project_dir => Root}
    ),
  ?assert(maps:get(count, Out) >= 1),
  ?assert(length(maps:get(files, Out)) >= 1),
  ok.
