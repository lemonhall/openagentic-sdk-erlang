-module(openagentic_workflow_engine_decision_route_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_workflow_engine_test_workflows_a, [
  write_workflow/1,
  write_workflow_task_filter/1,
  write_workflow_retry/1
]).
-import(openagentic_workflow_engine_test_workflows_b, [
  write_workflow_provider_retry/2,
  write_workflow_decision_route/1
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

