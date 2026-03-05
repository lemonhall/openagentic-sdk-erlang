-module(openagentic_workflow_dsl_test).

-include_lib("eunit/include/eunit.hrl").

loads_repo_fixture_test() ->
  Root = repo_root(),
  {ok, Wf} = openagentic_workflow_dsl:load_and_validate(Root, "workflows/three-provinces-six-ministries.v1.json", #{}),
  ?assertEqual(<<"1.0">>, maps:get(<<"workflow_version">>, Wf)),
  ?assert(maps:is_key(<<"steps_by_id">>, Wf)),
  ?assertEqual(<<"taizi_route">>, maps:get(<<"start_step_id">>, Wf)).

missing_prompt_file_is_error_test() ->
  Root = test_root(),
  ok = write_file(filename:join([Root, "workflows", "prompts", "x.md"]), <<"# ok\n">>),
  Workflow =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[{",
      "\"id\":\"s1\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/missing.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}]}">>,
  ok = write_file(filename:join([Root, "workflows", "w.json"]), Workflow),
  {error, {invalid_workflow_dsl, Errors}} = openagentic_workflow_dsl:load_and_validate(Root, "workflows/w.json", #{}),
  ?assert(has_error_code(Errors, <<"missing_file">>)).

unknown_guard_type_is_error_test() ->
  Root = test_root(),
  ok = write_file(filename:join([Root, "workflows", "prompts", "p.md"]), <<"# ok\n">>),
  Workflow =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[{",
      "\"id\":\"s1\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/p.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[{\"type\":\"nope\"}],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}]}">>,
  ok = write_file(filename:join([Root, "workflows", "w.json"]), Workflow),
  {error, {invalid_workflow_dsl, Errors}} = openagentic_workflow_dsl:load_and_validate(Root, "workflows/w.json", #{}),
  ?assert(has_error_code(Errors, <<"unknown_guard_type">>)).

no_terminal_path_is_error_test() ->
  Root = test_root(),
  ok = write_file(filename:join([Root, "workflows", "prompts", "p.md"]), <<"# ok\n">>),
  Workflow =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[",
      "{",
      "\"id\":\"a\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/p.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":\"b\",",
      "\"on_fail\":\"b\"",
      "},",
      "{",
      "\"id\":\"b\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"a\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/p.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":\"a\",",
      "\"on_fail\":\"a\"",
      "}",
      "]}">>,
  ok = write_file(filename:join([Root, "workflows", "w.json"]), Workflow),
  {error, {invalid_workflow_dsl, Errors}} = openagentic_workflow_dsl:load_and_validate(Root, "workflows/w.json", #{}),
  ?assert(has_error_code(Errors, <<"no_terminal">>)).

has_error_code(Errors, Code) ->
  lists:any(fun (E) -> maps:get(code, E, <<>>) =:= Code end, Errors).

repo_root() ->
  {ok, Cwd} = file:get_cwd(),
  openagentic_cli:resolve_project_dir_for_test(Cwd).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_workflow_dsl_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "workflows", "prompts", "x"])),
  Tmp.

write_file(Path, Bin) ->
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  file:write_file(Path, Bin).
