-module(openagentic_workflow_engine_core_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_workflow_engine_test_workflows_a, [
  write_workflow/1,
  write_workflow_task_filter/1,
  write_workflow_retry/1
]).
-import(openagentic_workflow_engine_test_utils, [
  test_root/0,
  write_file/2,
  last_run_start_step_id/1,
  last_step_output/2,
  find_first_event/2,
  find_last_event/2,
  ensure_map/1,
  ensure_list_value/1,
  to_bin/1,
  find_step_by_id/2,
  assert_prompt_has_staging_constraints/2
]).

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

workflow_engine_keeps_one_explicit_time_context_across_steps_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  _ = erlang:erase(openagentic_test_workflow_time_context),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      TimeContext = maps:get(time_context, Ctx, undefined),
      ?assert(is_map(TimeContext)),
      ?assertEqual(<<"Asia/Shanghai">>, maps:get(timezone, TimeContext, undefined)),
      ?assertEqual(<<"+08:00">>, maps:get(utc_offset, TimeContext, undefined)),
      ?assert(maps:get(current_local_time, TimeContext, undefined) =/= undefined),
      case erlang:get(openagentic_test_workflow_time_context) of
        undefined -> erlang:put(openagentic_test_workflow_time_context, TimeContext);
        Prev -> ?assertEqual(Prev, TimeContext)
      end,
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
  Init = find_first_event(Events, <<"workflow.init">>),
  RunStart = find_last_event(Events, <<"workflow.run.start">>),
  InitTc = ensure_map(maps:get(<<"time_context">>, Init, #{})),
  RunStartTc = ensure_map(maps:get(<<"time_context">>, RunStart, #{})),
  ?assertEqual(<<"Asia/Shanghai">>, maps:get(<<"timezone">>, InitTc, undefined)),
  ?assertEqual(InitTc, RunStartTc),
  ok.

workflow_engine_persists_time_context_into_step_sessions_test() ->
  Root = test_root(),
  ok = write_workflow(Root),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"a">> -> {ok, <<"# A\n\nok\n">>};
        <<"b">> -> {ok, <<"{\"decision\":\"approve\",\"reasons\":[],\"required_changes\":[]}">>};
        _ -> {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w.json", <<"hello">>, Opts),
  ?assertEqual(<<"completed">>, maps:get(status, Res)),
  WfSid = maps:get(workflow_session_id, Res),
  Events = openagentic_session_store:read_events(Root, WfSid),
  [FirstStepStart | _] = [E || E <- ensure_list_value(Events), maps:get(<<"type">>, ensure_map(E), <<>>) =:= <<"workflow.step.start">>],
  StepSid = to_bin(maps:get(<<"step_session_id">>, ensure_map(FirstStepStart), <<>>)),
  StepDir = openagentic_session_store:session_dir(Root, StepSid),
  StepMeta = openagentic_json:decode(element(2, file:read_file(filename:join([StepDir, "meta.json"])))),
  StepMetaTc = ensure_map(maps:get(<<"time_context">>, maps:get(<<"metadata">>, StepMeta, #{}), #{})),
  ?assertEqual(<<"Asia/Shanghai">>, maps:get(<<"timezone">>, StepMetaTc, undefined)),
  ?assertEqual(<<"UTC+08:00 / 东八区"/utf8>>, maps:get(<<"timezone_label">>, StepMetaTc, undefined)),
  [StepInit | _] = [E || E <- openagentic_session_store:read_events(Root, StepSid), maps:get(<<"type">>, ensure_map(E), <<>>) =:= <<"system.init">>],
  StepInitTc = ensure_map(maps:get(<<"time_context">>, ensure_map(StepInit), #{})),
  ?assertEqual(StepMetaTc, StepInitTc),
  ok.

