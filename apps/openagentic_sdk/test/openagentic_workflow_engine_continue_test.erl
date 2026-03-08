-module(openagentic_workflow_engine_continue_test).

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

workflow_engine_does_not_retry_transient_provider_timeout_without_retry_policy_test() ->
  Root = test_root(),
  ok = write_workflow_provider_retry(Root, false),
  Tab = ets:new(workflow_engine_no_retry_tab, [public]),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"draft">> ->
          {ok, <<"# Draft\n\nok\n">>};
        <<"aggregate">> ->
          _ = ets:update_counter(Tab, aggregate_attempts, 1, {aggregate_attempts, 0}),
          {error, timeout};
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  try
    {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_provider_retry.json", <<"hello">>, Opts),
    ?assertEqual(<<"failed">>, maps:get(status, Res)),
    ?assertEqual(1, ets:lookup_element(Tab, aggregate_attempts, 2)),
    Events = openagentic_session_store:read_events(Root, maps:get(workflow_session_id, Res)),
    ?assert(
      lists:any(
        fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.guard.fail">> end,
        Events
      )
    ),
    ?assert(
      lists:any(
        fun (E) ->
          maps:get(<<"type">>, E, <<>>) =:= <<"workflow.transition">>
          andalso maps:get(<<"outcome">>, E, <<>>) =:= <<"fail">>
        end,
        Events
      )
    ),
    ?assert(
      lists:any(
        fun (E) ->
          maps:get(<<"type">>, E, <<>>) =:= <<"workflow.done">>
          andalso maps:get(<<"status">>, E, <<>>) =:= <<"failed">>
        end,
        Events
      )
    )
  after
    ets:delete(Tab)
  end.

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

