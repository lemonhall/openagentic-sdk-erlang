-module(openagentic_workflow_engine_contracts_test).

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

