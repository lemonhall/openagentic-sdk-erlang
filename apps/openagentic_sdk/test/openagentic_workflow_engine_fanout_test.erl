-module(openagentic_workflow_engine_fanout_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_workflow_engine_test_workflows_c, [
  write_workflow_fanout/1
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

fanout_wait_does_not_require_down_after_result_test() ->
  Parent = self(),
  Worker =
    spawn(
      fun () ->
        Child = spawn(fun () -> receive after infinity -> ok end end),
        Ref = erlang:monitor(process, Child),
        Result =
          {ok,
            #{
              attempt => 1,
              output => <<"# Result\n\nok\n">>,
              parsed => #{type => markdown},
              output_format => <<"markdown">>,
              step_session_id => <<"fanout_step_session">>
            }},
        self() ! {fanout_result, <<"leaf_a">>, Result},
        Res = openagentic_workflow_engine:wait_for_fanout_for_test(#{Ref => #{step_id => <<"leaf_a">>, pid => Child}}, #{}, #{}),
        Parent ! {fanout_wait_done, Res},
        exit(Child, kill)
      end
    ),
  receive
    {fanout_wait_done, {ok, Results}} ->
      ?assertMatch(#{<<"leaf_a">> := {ok, _}}, Results)
  after 500 ->
    exit(Worker, kill),
    ?assert(false)
  end.

