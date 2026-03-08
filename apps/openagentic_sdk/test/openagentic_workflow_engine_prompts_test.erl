-module(openagentic_workflow_engine_prompts_test).

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

three_provinces_aggregate_prompt_uses_poem_staging_paths_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_aggregate.md"])),
  lists:foreach(
    fun (Path) ->
      ?assert(binary:match(Bin, Path) =/= nomatch)
    end,
    [
      <<"workspace:staging/hubu/poem.md">>,
      <<"workspace:staging/libu/poem.md">>,
      <<"workspace:staging/bingbu/poem.md">>,
      <<"workspace:staging/xingbu/poem.md">>,
      <<"workspace:staging/gongbu/poem.md">>,
      <<"workspace:staging/libu_hr/poem.md">>
    ]
  ),
  lists:foreach(
    fun (OldName) ->
      ?assertEqual(nomatch, binary:match(Bin, OldName))
    end,
    [
      <<"户部.md">>,
      <<"礼部.md">>,
      <<"兵部.md">>,
      <<"刑部.md">>,
      <<"工部.md">>,
      <<"吏部.md">>
    ]
  ),
  ?assertEqual(nomatch, binary:match(Bin, <<"workspace:deliverables/六部各赋诗一首.md">>)),
  ok.


three_provinces_dispatch_prompt_treats_assertive_public_events_as_working_facts_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_dispatch.md"])),
  ?assert(binary:match(Bin, <<"PUBLIC_EVENTS_USE_WORKING_FACTS">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"NO_MECHANICAL_UNVERIFIED_CAVEAT">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"WebSearch/WebFetch">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"workspace:staging/gongbu/poem.md">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"workspace:staging/libu/poem.md">>) =/= nomatch),
  ok.

three_provinces_dispatch_prompt_enables_argument_level_evidence_augmentation_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_dispatch.md"])),
  ?assert(binary:match(Bin, <<"ARGUMENT_EVIDENCE_AUGMENTATION">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"Task(agent=\"research\"">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"不要把整篇改写成 research 报告"/utf8>>) =/= nomatch),
  ok.

