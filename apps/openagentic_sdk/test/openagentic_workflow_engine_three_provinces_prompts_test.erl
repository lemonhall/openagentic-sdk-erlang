-module(openagentic_workflow_engine_three_provinces_prompts_test).

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

three_provinces_ministry_steps_allow_task_research_subagent_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "three-provinces-six-ministries.v1.json"])),
  Wf = ensure_map(openagentic_json:decode(Bin)),
  Steps = ensure_list_value(maps:get(<<"steps">>, Wf, [])),
  lists:foreach(
    fun (StepId) ->
      Step = find_step_by_id(StepId, Steps),
      Policy = ensure_map(maps:get(<<"tool_policy">>, Step, #{})),
      Allow = [to_bin(X) || X <- ensure_list_value(maps:get(<<"allow">>, Policy, []))],
      Deny = [to_bin(X) || X <- ensure_list_value(maps:get(<<"deny">>, Policy, []))],
      ?assert(lists:member(<<"Task">>, Allow)),
      ?assertEqual(false, lists:member(<<"Task">>, Deny))
    end,
    [
      <<"hubu_data">>,
      <<"libu_docs">>,
      <<"bingbu_engineering">>,
      <<"xingbu_compliance">>,
      <<"gongbu_infra">>,
      <<"libu_hr_people">>
    ]
  ),
  ok.

three_provinces_ministry_prompts_embed_argument_level_evidence_rules_test() ->
  lists:foreach(
    fun (Path) ->
      {ok, Bin} = file:read_file(Path),
      ?assert(binary:match(Bin, <<"ARGUMENT_EVIDENCE_AUGMENTATION">>) =/= nomatch),
      ?assert(binary:match(Bin, <<"Task(agent=\"research\"">>) =/= nomatch),
      ?assert(binary:match(Bin, <<"不要把整篇改写成 research 报告"/utf8>>) =/= nomatch)
    end,
    [
      filename:join(["workflows", "prompts", "hubu_data.md"]),
      filename:join(["workflows", "prompts", "libu_docs.md"]),
      filename:join(["workflows", "prompts", "bingbu_engineering.md"]),
      filename:join(["workflows", "prompts", "xingbu_compliance.md"]),
      filename:join(["workflows", "prompts", "gongbu_infra.md"]),
      filename:join(["workflows", "prompts", "libu_hr_people.md"]),
      filename:join(["workflows", "prompts", "zhongshu_plan.md"])
    ]
  ),
  ok.

three_provinces_aggregate_prompt_requires_substantive_synthesis_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_aggregate.md"])),
  ?assert(binary:match(Bin, <<"AGGREGATE_SUBSTANTIVE_SYNTHESIS">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"NO_FILE_STATUS_AS_MAIN_CONTENT">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"workspace:staging/libu_hr/poem.md">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"workspace:staging/hubu/poem.md">>) =/= nomatch),
  ok.

three_provinces_aggregate_prompt_requires_owned_judgment_and_real_escalation_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_aggregate.md"])),
  ?assert(binary:match(Bin, <<"AGGREGATE_OWN_JUDGMENT_AND_TRADEOFF">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"AGGREGATE_REAL_BLOCKERS_ONLY">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"Markdown">>) =/= nomatch),
  ok.

three_provinces_aggregate_prompt_preserves_utf8_text_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "shangshu_aggregate.md"])),
  ?assert(binary:match(Bin, <<"尚书省的定稿官"/utf8>>) =/= nomatch),
  ?assert(binary:match(Bin, <<"需要皇上裁决"/utf8>>) =/= nomatch),
  ok.

three_provinces_taizi_solo_prompt_preserves_utf8_text_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "taizi_solo.md"])),
  ?assert(binary:match(Bin, <<"太子：独办回信"/utf8>>) =/= nomatch),
  ?assert(binary:match(Bin, <<"对皇上的回信"/utf8>>) =/= nomatch),
  ok.

three_provinces_taizi_reply_prompt_avoids_overcautious_hypothetical_framing_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "taizi_reply.md"])),
  ?assert(binary:match(Bin, <<"REPLY_AVOID_HYPOTHETICAL_PADDING">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"REPLY_USE_PUBLIC_SITUATION_NATURAL_WORDING">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"taizi_reply">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"Markdown">>) =/= nomatch),
  ok.


three_provinces_taizi_solo_prompt_avoids_overcautious_hypothetical_framing_test() ->
  {ok, Bin} = file:read_file(filename:join(["workflows", "prompts", "taizi_solo.md"])),
  ?assert(binary:match(Bin, <<"SOLO_AVOID_HYPOTHETICAL_PADDING">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"SOLO_USE_PUBLIC_SITUATION_NATURAL_WORDING">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"taizi_solo">>) =/= nomatch),
  ?assert(binary:match(Bin, <<"Markdown">>) =/= nomatch),
  ok.

