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

workflow_engine_filters_tasks_input_by_ministry_role_test() ->
  Root = test_root(),
  ok = write_workflow_task_filter(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      Prompt = maps:get(user_prompt, Ctx, <<>>),
      case StepId of
        <<"dispatch">> ->
          {ok,
            <<
              "{",
              "\"tasks\":[",
              "{\"id\":\"t-hubu\",\"title\":\"hubu\",\"ministry\":\"hubu\",\"definition_of_done\":[],\"needs_user_confirm\":false},",
              "{\"id\":\"t-gongbu\",\"title\":\"gongbu\",\"ministry\":\"gongbu\",\"definition_of_done\":[],\"needs_user_confirm\":false}",
              "]",
              "}"
            >>};
        <<"gongbu">> ->
          %% Input should be filtered down to only this ministry's tasks.
          ?assert(binary:match(Prompt, <<"\"ministry\":\"gongbu\"">>) =/= nomatch),
          ?assertEqual(nomatch, binary:match(Prompt, <<"\"ministry\":\"hubu\"">>)),
          {ok, <<"# R\n\nok\n">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_filter.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
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
      %% Prompt must be valid UTF-8 so it can be persisted + sent to providers.
      ?assert(is_list(unicode:characters_to_list(Prompt, utf8))),
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

workflow_engine_continue_after_completed_restarts_from_start_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      Prompt = maps:get(user_prompt, Ctx, <<>>),
      case StepId of
        <<"a">> ->
          %% Echo whether the followup made it into the assembled prompt.
          Out =
            case binary:match(Prompt, <<"second">>) of
              nomatch -> <<"# A\n\nfirst\n">>;
              _ -> <<"# A\n\nsecond\n">>
            end,
          {ok, Out};
        <<"b">> ->
          {ok, <<"{\"decision\":\"approve\",\"reasons\":[],\"required_changes\":[]}">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res1} = openagentic_workflow_engine:run(Root, "workflows/w.json", <<"first">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res1)),
  WfSid = maps:get(workflow_session_id, Res1),

  {ok, Res2} = openagentic_workflow_engine:continue(Root, WfSid, <<"second">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res2)),
  ?assertEqual(WfSid, maps:get(workflow_session_id, Res2)),

  Events = openagentic_session_store:read_events(Root, WfSid),
  ?assertEqual(<<"a">>, last_run_start_step_id(Events)),
  ?assert(binary:match(last_step_output(Events, <<"a">>), <<"second">>) =/= nomatch),
  ok.

workflow_engine_continue_after_failed_includes_guard_reasons_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      Prompt = maps:get(user_prompt, Ctx, <<>>),
      case StepId of
        <<"a">> ->
          case binary:match(Prompt, <<"missing sections: A">>) of
            nomatch ->
              %% First run: fail the contract.
              {ok, <<"nope\n">>};
            _ ->
              %% Continue run: must carry the guard failure reason.
              {ok, <<"# A\n\nok\n">>}
          end;
        <<"b">> ->
          {ok, <<"{\"decision\":\"approve\",\"reasons\":[],\"required_changes\":[]}">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res1} = openagentic_workflow_engine:run(Root, "workflows/w.json", <<"hello">>, Opts),
  ?assertEqual(<<"failed">>, maps:get(status, Res1)),
  WfSid = maps:get(workflow_session_id, Res1),

  {ok, Res2} = openagentic_workflow_engine:continue(Root, WfSid, <<"fix it">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res2)),
  ok.

workflow_engine_decision_on_decision_routes_reject_test() ->
  Root = test_root(),
  ok = write_workflow_decision_route(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"a">> ->
          {ok, <<"# A\n\nok\n">>};
        <<"b">> ->
          {ok, <<"{\"decision\":\"reject\",\"reasons\":[\"r1\"],\"required_changes\":[\"c1\"]}">>};
        <<"c">> ->
          {ok, <<"# C\n\nshould not run\n">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_decision.json", <<"hello">>, Opts),
  %% reject should route back to "a" and never reach "c"; max_attempts=1 makes it fail.
  ?assertEqual(<<"failed">>, maps:get(status, Res)),
  WfSid = maps:get(workflow_session_id, Res),
  Events = openagentic_session_store:read_events(Root, WfSid),
  ?assert(not lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.start">> andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"c">> end, Events)),
  ok.

workflow_engine_fanout_join_parallel_steps_and_join_test() ->
  Root = test_root(),
  ok = write_workflow_fanout(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      Prompt = maps:get(user_prompt, Ctx, <<>>),
      case StepId of
        <<"dispatch">> ->
          {ok,
            <<
              "{",
              "\"tasks\":[",
              "{\"id\":\"t-hubu\",\"title\":\"hubu\",\"ministry\":\"hubu\",\"definition_of_done\":[\"write workspace:staging/hubu/poem.md\"],\"needs_user_confirm\":false},",
              "{\"id\":\"t-gongbu\",\"title\":\"gongbu\",\"ministry\":\"gongbu\",\"definition_of_done\":[\"write workspace:staging/gongbu/poem.md\"],\"needs_user_confirm\":false}",
              "]",
              "}"
            >>};
        <<"hubu">> ->
          timer:sleep(120),
          ?assert(binary:match(Prompt, <<"\"ministry\":\"hubu\"">>) =/= nomatch),
          ?assertEqual(nomatch, binary:match(Prompt, <<"\"ministry\":\"gongbu\"">>)),
          ?assert(binary:match(Prompt, <<"workspace:staging/hubu/poem.md">>) =/= nomatch),
          {ok, <<"# Result\n\nhubu finished\n\n# Artifacts\n\n- workspace:staging/hubu/poem.md\n\n# Handoff\n\nplease join\n">>};
        <<"gongbu">> ->
          timer:sleep(40),
          ?assert(binary:match(Prompt, <<"\"ministry\":\"gongbu\"">>) =/= nomatch),
          ?assertEqual(nomatch, binary:match(Prompt, <<"\"ministry\":\"hubu\"">>)),
          ?assert(binary:match(Prompt, <<"workspace:staging/gongbu/poem.md">>) =/= nomatch),
          {ok, <<"# Result\n\ngongbu finished\n\n# Artifacts\n\n- workspace:staging/gongbu/poem.md\n\n# Handoff\n\nplease join\n">>};
        <<"aggregate">> ->
          ?assert(binary:match(Prompt, <<"hubu finished">>) =/= nomatch),
          ?assert(binary:match(Prompt, <<"gongbu finished">>) =/= nomatch),
          {ok, <<"# Summary\n\nall done\n">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_fanout.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
  WfSid = maps:get(workflow_session_id, Res),
  Events = openagentic_session_store:read_events(Root, WfSid),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.start">> andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"fanout">> end, Events)),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.output">> andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"hubu">> end, Events)),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.output">> andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"gongbu">> end, Events)),
  ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.output">> andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"aggregate">> end, Events)),
  ok.

workflow_engine_fanout_join_workflow_event_seq_monotonic_test() ->
  Root = test_root(),
  ok = write_workflow_fanout(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"dispatch">> ->
          {ok,
            <<
              "{",
              "\"tasks\":[",
              "{\"id\":\"t-hubu\",\"title\":\"hubu\",\"ministry\":\"hubu\",\"definition_of_done\":[],\"needs_user_confirm\":false},",
              "{\"id\":\"t-gongbu\",\"title\":\"gongbu\",\"ministry\":\"gongbu\",\"definition_of_done\":[],\"needs_user_confirm\":false}",
              "]",
              "}"
            >>};
        <<"hubu">> ->
          timer:sleep(80),
          {ok, <<"# Result\n\nhubu\n\n# Artifacts\n\n- ok\n\n# Handoff\n\njoin\n">>};
        <<"gongbu">> ->
          timer:sleep(10),
          {ok, <<"# Result\n\ngongbu\n\n# Artifacts\n\n- ok\n\n# Handoff\n\njoin\n">>};
        <<"aggregate">> ->
          {ok, <<"# Summary\n\nall done\n">>};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_fanout.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
  Events = openagentic_session_store:read_events(Root, maps:get(workflow_session_id, Res)),
  Seqs = [maps:get(<<"seq">>, E, maps:get(seq, E, -1)) || E <- Events],
  ?assertEqual(Seqs, lists:sort(Seqs)),
  ?assertEqual(length(Seqs), length(lists:usort(Seqs))),
  ok.

three_provinces_workflow_uses_fanout_join_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "three-provinces-six-ministries.v1.json"])),
  Wf = openagentic_json:decode(Bin),
  Steps = maps:get(<<"steps">>, Wf),
  Dispatch = find_step_by_id(<<"shangshu_dispatch">>, Steps),
  Fanout = find_step_by_id(<<"six_ministries_fanout">>, Steps),
  Hubu = find_step_by_id(<<"hubu_data">>, Steps),
  Gongbu = find_step_by_id(<<"gongbu_infra">>, Steps),
  ?assertEqual(<<"six_ministries_fanout">>, maps:get(<<"on_pass">>, Dispatch)),
  ?assertEqual(<<"fanout_join">>, maps:get(<<"executor">>, Fanout)),
  ?assertEqual(<<"shangshu_aggregate">>, maps:get(<<"join">>, maps:get(<<"fanout">>, Fanout))),
  ?assertEqual(null, maps:get(<<"on_pass">>, Hubu)),
  ?assertEqual(<<"hubu_data">>, maps:get(<<"on_fail">>, Hubu)),
  ?assertEqual(null, maps:get(<<"on_pass">>, Gongbu)),
  ?assertEqual(<<"gongbu_infra">>, maps:get(<<"on_fail">>, Gongbu)),
  ok.

three_provinces_ministry_prompts_use_staging_paths_test() ->
  assert_prompt_has_staging_constraints("workflows/prompts/hubu_data.md", <<"hubu">>),
  assert_prompt_has_staging_constraints("workflows/prompts/libu_docs.md", <<"libu">>),
  assert_prompt_has_staging_constraints("workflows/prompts/bingbu_engineering.md", <<"bingbu">>),
  assert_prompt_has_staging_constraints("workflows/prompts/xingbu_compliance.md", <<"xingbu">>),
  assert_prompt_has_staging_constraints("workflows/prompts/gongbu_infra.md", <<"gongbu">>),
  assert_prompt_has_staging_constraints("workflows/prompts/libu_hr_people.md", <<"libu_hr">>),
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

write_workflow_task_filter(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "dispatch.md"]), <<"# dispatch prompt\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "gongbu.md"]), <<"# gongbu prompt\n">>),
  Json =
    <<
      "{",
      "\"workflow_version\":\"1.0\",",
      "\"name\":\"t\",",
      "\"steps\":[",
      "{",
      "\"id\":\"dispatch\",",
      "\"role\":\"shangshu\",",
      "\"input\":{\"type\":\"controller_input\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/dispatch.md\"},",
      "\"output_contract\":{\"type\":\"json_object\"},",
      "\"guards\":[{\"type\":\"regex_must_match\",\"pattern\":\"\\\\\\\"tasks\\\\\\\"\\\\s*:\"}],",
      "\"on_pass\":\"gongbu\",",
      "\"on_fail\":null",
      "},",
      "{",
      "\"id\":\"gongbu\",",
      "\"role\":\"gongbu\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"dispatch\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/gongbu.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"R\"]},",
      "\"guards\":[],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}",
      "]}">>,
  write_file(filename:join([Root, "workflows", "w_filter.json"]), Json).

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

write_workflow_decision_route(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "a.md"]), <<"# prompt a\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "b.md"]), <<"# prompt b\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "c.md"]), <<"# prompt c\n">>),
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
      "\"on_decision\":{\"approve\":\"c\",\"reject\":\"a\"},",
      "\"on_pass\":\"c\",",
      "\"on_fail\":null,",
      "\"max_attempts\":1",
      "},",
      "{",
      "\"id\":\"c\",",
      "\"role\":\"r\",",
      "\"input\":{\"type\":\"step_output\",\"step_id\":\"b\"},",
      "\"prompt\":{\"type\":\"file\",\"path\":\"workflows/prompts/c.md\"},",
      "\"output_contract\":{\"type\":\"markdown_sections\",\"required\":[\"C\"]},",
      "\"guards\":[],",
      "\"on_pass\":null,",
      "\"on_fail\":null",
      "}",
      "]}">>,
  write_file(filename:join([Root, "workflows", "w_decision.json"]), Json).

write_workflow_fanout(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "dispatch.md"]), <<"# dispatch\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "hubu.md"]), <<"只允许写入 workspace:staging/hubu/poem.md\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "gongbu.md"]), <<"只允许写入 workspace:staging/gongbu/poem.md\n">>),
  ok = write_file(filename:join([Root, "workflows", "prompts", "aggregate.md"]), <<"# aggregate\n">>),
  Json =
    openagentic_json:encode(
      #{
        workflow_version => <<"1.0">>,
        name => <<"fanout">>,
        steps => [
          #{
            id => <<"dispatch">>,
            role => <<"shangshu">>,
            input => #{type => <<"controller_input">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/dispatch.md">>},
            output_contract => #{type => <<"json_object">>, schema_hint => #{tasks => []}},
            guards => [#{type => <<"regex_must_match">>, pattern => <<"tasks">>}],
            on_pass => <<"fanout">>,
            on_fail => null
          },
          #{
            id => <<"fanout">>,
            role => <<"shangshu">>,
            executor => <<"fanout_join">>,
            fanout => #{steps => [<<"hubu">>, <<"gongbu">>], join => <<"aggregate">>, max_concurrency => 2, fail_fast => false},
            on_fail => null
          },
          #{
            id => <<"hubu">>,
            role => <<"hubu">>,
            input => #{type => <<"step_output">>, step_id => <<"dispatch">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/hubu.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Result">>, <<"Artifacts">>, <<"Handoff">>]},
            guards => [],
            on_pass => null,
            on_fail => <<"hubu">>,
            max_attempts => 2
          },
          #{
            id => <<"gongbu">>,
            role => <<"gongbu">>,
            input => #{type => <<"step_output">>, step_id => <<"dispatch">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/gongbu.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Result">>, <<"Artifacts">>, <<"Handoff">>]},
            guards => [],
            on_pass => null,
            on_fail => <<"gongbu">>,
            max_attempts => 2
          },
          #{
            id => <<"aggregate">>,
            role => <<"shangshu">>,
            input => #{type => <<"merge">>, sources => [#{type => <<"step_output">>, step_id => <<"hubu">>}, #{type => <<"step_output">>, step_id => <<"gongbu">>}]},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/aggregate.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Summary">>]},
            guards => [],
            on_pass => null,
            on_fail => null
          }
        ]
      }
    ),
  write_file(filename:join([Root, "workflows", "w_fanout.json"]), <<Json/binary, "\n">>).

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

last_run_start_step_id(Events0) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case maps:get(<<"type">>, E, <<>>) of
        <<"workflow.run.start">> -> maps:get(<<"start_step_id">>, E, Best0);
        _ -> Best0
      end
    end,
    <<>>,
    Events
  ).

last_step_output(Events0, StepId0) ->
  Events = ensure_list_value(Events0),
  StepId = to_bin(StepId0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case maps:get(<<"type">>, E, <<>>) of
        <<"workflow.step.output">> ->
          case maps:get(<<"step_id">>, E, <<>>) of
            StepId -> maps:get(<<"output">>, E, Best0);
            _ -> Best0
          end;
        _ ->
          Best0
      end
    end,
    <<>>,
    Events
  ).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(B) when is_binary(B) -> [B];
ensure_list_value(undefined) -> [];
ensure_list_value(null) -> [];
ensure_list_value(Other) -> [Other].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

find_step_by_id(_Id, []) ->
  erlang:error(step_not_found);
find_step_by_id(Id, [#{<<"id">> := Id} = Step | _]) ->
  Step;
find_step_by_id(Id, [_ | Rest]) ->
  find_step_by_id(Id, Rest).

assert_prompt_has_staging_constraints(Path, Ministry) ->
  {ok, Bin} = file:read_file(Path),
  ?assert(binary:match(Bin, iolist_to_binary([<<"workspace:staging/">>, Ministry, <<"/poem.md">>])) =/= nomatch),
  ?assert(binary:match(Bin, iolist_to_binary([<<"workspace:staging/">>, Ministry, <<"/...">>])) =/= nomatch),
  ?assertEqual(nomatch, binary:match(Bin, <<"workspace:deliverables/">>)).
