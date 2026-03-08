-module(openagentic_workflow_engine_retry_test).

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

workflow_engine_retries_transient_provider_timeout_when_retry_policy_enabled_test() ->
  Root = test_root(),
  ok = write_workflow_provider_retry(Root, true),
  Tab = ets:new(workflow_engine_retry_tab, [public]),
  Exec =
    fun (Ctx) ->
      StepId = maps:get(step_id, Ctx),
      case StepId of
        <<"draft">> ->
          {ok, <<"# Draft\n\nok\n">>};
        <<"aggregate">> ->
          Count = ets:update_counter(Tab, aggregate_attempts, 1, {aggregate_attempts, 0}),
          case Count of
            1 -> {error, timeout};
            _ -> {ok, <<"# Summary\n\nok\n">>}
          end;
        _ ->
          {error, unknown_step}
      end
    end,
  Opts = #{session_root => Root, step_executor => Exec, strict_unknown_fields => true},
  try
    {ok, Res} = openagentic_workflow_engine:run(Root, "workflows/w_provider_retry.json", <<"hello">>, Opts),
    ?assertEqual(<<"completed">>, maps:get(status, Res)),
    ?assertEqual(2, ets:lookup_element(Tab, aggregate_attempts, 2)),
    Events = openagentic_session_store:read_events(Root, maps:get(workflow_session_id, Res)),
    ?assert(
      lists:any(
        fun (E) ->
          maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.output">>
          andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"aggregate">>
        end,
        Events
      )
    ),
    ?assert(
      lists:any(
        fun (E) ->
          maps:get(<<"type">>, E, <<>>) =:= <<"workflow.step.pass">>
          andalso maps:get(<<"step_id">>, E, <<>>) =:= <<"aggregate">>
        end,
        Events
      )
    ),
    ?assert(lists:any(fun (E) -> maps:get(<<"type">>, E, <<>>) =:= <<"workflow.done">> end, Events))
  after
    ets:delete(Tab)
  end.

