-module(openagentic_workflow_engine_test).

-include_lib("eunit/include/eunit.hrl").

workflow_engine_happy_path_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"a">> ->
          {ok, <<"# A\n\nok\n">>};
        <<"b">> ->
          {ok, <<"{\"decision\":\"approve\",\"reasons\":[],\"required_changes\":[]}">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
  WfSid = maps:get(workflow_session_id, Res),
  Events = openagentic_session_store:read_events(Root, WfSid),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.init">> end, Events)),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.done">> end, Events)),
  ok.

workflow_engine_contract_fail_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"a">> ->
          %% Missing required section "A"
          {ok, <<"nope\n">>};
        _ ->
          {ok, <<"">>}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w.json", <<"hello">>, Opts),
  ?assertEqual(<<"failed">>, maps:get(status, Res)),
  ok.

workflow_engine_retry_includes_failure_reason_test() ->
  Root = test_root(),
  ok = write_workflow_retry(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      Attempt = maps:get(attempt, Ctx, 1),
      Prompt = maps:get(user_prompt, Ctx, <<>>),
      case {StepId, Attempt} of
        {<<"a">>, 1} ->
          %% Missing required section "A"
          {ok, <<"nope\n">>};
        {<<"a">>, 2} ->
          %% Retry should carry the previous failure reason to help self-correct.
          ?assert(binary:match(Prompt, <<"missing sections: A">>) =/= nomatch),
          {ok, <<"# A\n\nok\n">>};
        {<<"b">>, _} ->
          {ok, <<"{\"decision\":\"approve\",\"reasons\":[],\"required_changes\":[]}">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_retry.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
  ok.

write_workflow(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "a.md"]), <<"# prompt a\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "b.md"]), <<"# prompt b\n">>),
  Json =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[",
      "{",
      "\"id\":\"a\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/a.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":\"b\",",
      "\"on_fail\":null",
      "},",
      "{",
      "\"id\":\"b\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"a\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/b.md\"},",
      "\"output_contract\":{\"type\":\"decision\",\"allowed\":[\"approve\",\"reject\"],\"format\":\"json\",\"fields\":[\"decision\",\"reasons\",\"required_changes\"]},",
      "\"guards\":[{\"type\":\"decision_requires_reasons\",\"when\":\"reject\"}],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}",
      "]}">>,
  write_file(filename:join([Root, "workflows", "w.json"]), Json).

write_workflow_retry(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "a.md"]), <<"# prompt a\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "b.md"]), <<"# prompt b\n">>),
  Json =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[",
      "{",
      "\"id\":\"a\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/a.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"A\"]},",
      "\"guards\":[],",
      "\"on_pass\":\"b\",",
      "\"on_fail\":\"a\",",
      "\"max_attempts\":2",
      "},",
      "{",
      "\"id\":\"b\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"a\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/b.md\"},",
      "\"output_contract\":{\"type\":\"decision\",\"allowed\":[\"approve\",\"reject\"],\"format\":\"json\",\"fields\":[\"decision\",\"reasons\",\"required_changes\"]},",
      "\"guards\":[{\"type\":\"decision_requires_reasons\",\"when\":\"reject\"}],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}",
      "]}">>,
  write_file(filename:join([Root, "workflows", "w_retry.json"]), Json).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_workflow_engine_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "workflows", "prompts", "x"])),
  Tmp.

write_file(Path, Bin) ->
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  file:write_file(Path, Bin).
