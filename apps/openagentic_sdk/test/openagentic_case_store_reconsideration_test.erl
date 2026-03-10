-module(openagentic_case_store_reconsideration_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [
  create_case_fixture/1,
  id_of/1,
  deep_get/2,
  tmp_root/0
]).

observation_pack_review_and_reconsideration_snapshot_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),

  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Iran escalation observation pack">>,
          target_question => <<"Should the court reopen deliberation on Iran escalation signals?">>,
          task_bindings =>
            [
              #{task_id => lists:nth(1, TaskIds), role => <<"primary">>, required => true},
              #{task_id => lists:nth(2, TaskIds), role => <<"supporting">>, required => true}
            ],
          freshness_window => #{max_age_seconds => 86400},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  Pack = maps:get(pack, PackRes),
  PackId = id_of(Pack),
  ?assertEqual(<<"awaiting_inspection">>, deep_get(Pack, [state, status])),
  ?assertEqual(100, deep_get(Pack, [state, ready_score])),
  ?assertEqual([], deep_get(Pack, [state, missing_requirements])),

  {ok, ReviewRes} =
    erlang:apply(
      openagentic_case_store,
      inspect_observation_pack,
      [Root, #{case_id => CaseId, pack_id => PackId, inspected_by_op_id => <<"lemon">>}]
    ),
  Review = maps:get(inspection_review, ReviewRes),
  assert_review_process_trace(Review, <<"ready_for_reconsideration">>),
  ?assertEqual(<<"ready_for_reconsideration">>, deep_get(Review, [state, status])),
  ?assert(length(deep_get(Review, [spec, controversy_candidates])) >= 1),

  {ok, PackageRes} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  Package = maps:get(reconsideration_package, PackageRes),
  Mail = maps:get(mail, PackageRes),
  FrozenPayload = deep_get(Package, [ext, frozen_payload]),

  ?assertEqual(<<"ready">>, deep_get(Package, [state, status])),
  ?assertEqual(1, deep_get(Package, [state, version_no])),
  ?assertEqual(<<"PACK-", PackId/binary, "-V1">>, deep_get(Package, [state, display_code])),
  ?assertMatch(#{id := _}, maps:get(based_on_round, FrozenPayload)),
  ?assert(length(maps:get(baseline_facts, FrozenPayload)) >= 1),
  ?assert(length(maps:get(change_facts, FrozenPayload)) >= 1),
  [FirstChange | _] = maps:get(change_facts, FrozenPayload),
  ?assert(maps:get(category, FirstChange, undefined) =/= undefined),
  ?assertEqual(2, length(maps:get(reports, FrozenPayload))),
  ?assert(length(maps:get(controversies, maps:get(summary, FrozenPayload))) >= 1),
  ?assertEqual(<<"reconsideration_ready">>, deep_get(Mail, [spec, message_type])),
  ?assertEqual(id_of(Package), deep_get(maps:get(inspection_review, PackageRes), [links, derived_briefing_id])),

  {ok, Preview} = erlang:apply(openagentic_case_store, get_reconsideration_preview, [Root, CaseId, id_of(Package)]),
  ?assertEqual(id_of(Package), deep_get(maps:get(reconsideration_package, Preview), [header, id])),
  ?assertEqual(2, length(maps:get(reports, maps:get(preview, Preview)))),
  ok.

reconsideration_package_deferred_superseded_and_consumed_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),
  PackId = create_pack_and_review(Root, CaseId, TaskIds),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),

  {ok, PackageRes0} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  Package0 = maps:get(reconsideration_package, PackageRes0),
  Package0Id = id_of(Package0),
  ?assertEqual(1, deep_get(Package0, [state, version_no])),
  ?assertEqual(<<"PACK-", PackId/binary, "-V1">>, deep_get(Package0, [state, display_code])),
  ?assert(deep_get(maps:get(mail, PackageRes0), [links, source_op_id]) =/= undefined),

  {ok, DeferredRes} =
    erlang:apply(
      openagentic_case_store,
      defer_reconsideration_package,
      [Root, #{case_id => CaseId, package_id => Package0Id, acted_by_op_id => <<"lemon">>}]
    ),
  EncodedDeferred = openagentic_json:encode_safe(DeferredRes),
  Deferred = maps:get(reconsideration_package, DeferredRes),
  ?assert(byte_size(EncodedDeferred) > 0),
  ?assertEqual(<<"deferred">>, deep_get(Deferred, [state, status])),

  {ok, PackageRes1} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  EncodedPackageRes1 = openagentic_json:encode_safe(PackageRes1),
  Package1 = maps:get(reconsideration_package, PackageRes1),
  Package1Id = id_of(Package1),
  ?assert(byte_size(EncodedPackageRes1) > 0),
  ?assertEqual(2, deep_get(Package1, [state, version_no])),
  ?assertEqual(<<"PACK-", PackId/binary, "-V2">>, deep_get(Package1, [state, display_code])),

  {ok, OldPreview} = erlang:apply(openagentic_case_store, get_reconsideration_preview, [Root, CaseId, Package0Id]),
  ?assertEqual(<<"superseded">>, deep_get(maps:get(reconsideration_package, OldPreview), [state, status])),
  ?assertMatch(
    {error, reconsideration_package_superseded},
    erlang:apply(
      openagentic_case_store,
      start_reconsideration,
      [Root, #{case_id => CaseId, package_id => Package0Id, started_by_op_id => <<"lemon">>}]
    )
  ),

  {ok, StartedRes} =
    erlang:apply(
      openagentic_case_store,
      start_reconsideration,
      [Root, #{case_id => CaseId, package_id => Package1Id, started_by_op_id => <<"lemon">>}]
    ),
  Round = maps:get(round, StartedRes),
  Consumed = maps:get(reconsideration_package, StartedRes),
  WorkflowSessionId = deep_get(Round, [links, workflow_session_id]),
  SessionDir = openagentic_session_store:session_dir(Root, WorkflowSessionId),
  SessionMeta = openagentic_case_store_repo_persist:read_json(filename:join([SessionDir, "meta.json"])),
  ReconsiderationContext = deep_get(SessionMeta, [metadata, reconsideration_context]),
  Events = openagentic_session_store:read_events(Root, WorkflowSessionId),
  [SystemInit | _] = [E || E <- Events, maps:get(<<"type">>, E, <<>>) =:= <<"system.init">>],

  ?assert(WorkflowSessionId =/= <<>>),
  ?assertEqual(Package1Id, deep_get(Round, [links, reconsideration_package_id])),
  ?assertEqual(<<"consumed_by_round">>, deep_get(Consumed, [state, status])),
  ?assertEqual(id_of(Round), deep_get(Consumed, [links, consumed_by_round_id])),
  ?assertEqual(Package1Id, deep_get(ReconsiderationContext, [package_id])),
  ?assert(deep_get(ReconsiderationContext, [frozen_payload, summary]) =/= #{}),
  ?assertEqual(Package1Id, maps:get(<<"package_id">>, maps:get(<<"reconsideration_context">>, SystemInit, #{}), <<>>)),
  ?assert(maps:get(<<"summary">>, maps:get(<<"frozen_payload">>, maps:get(<<"reconsideration_context">>, SystemInit, #{}), #{}), #{}) =/= #{}),
  OperationPaths = filelib:wildcard(filename:join([CaseDir, "meta", "ops", "*.json"])),
  ?assertEqual(5, length(OperationPaths)),
  Operations = [openagentic_case_store_repo_persist:read_json(Path) || Path <- OperationPaths],
  OperationTypes = [deep_get(Op, [spec, op_type]) || Op <- Operations],
  ?assert(lists:member(<<"inspect_observation_pack">>, OperationTypes)),
  ?assert(lists:member(<<"create_reconsideration_package">>, OperationTypes)),
  ?assert(lists:member(<<"defer_reconsideration_package">>, OperationTypes)),
  ?assert(lists:member(<<"start_reconsideration">>, OperationTypes)),
  ?assertEqual(2, length([Type || Type <- OperationTypes, Type =:= <<"create_reconsideration_package">>])),
  ?assert(lists:all(fun (Op) -> deep_get(Op, [state, status]) =:= <<"applied">> end, Operations)),
  TimelinePath = filename:join([CaseDir, "meta", "timeline.jsonl"]),
  ?assert(filelib:is_file(TimelinePath)),
  TimelineEntries = [openagentic_case_store_repo_persist:decode_json(Line) || Line <- openagentic_case_store_test_support:file_lines(TimelinePath)],
  TimelineTypes = [maps:get(event_type, Entry) || Entry <- TimelineEntries],
  ?assert(lists:member(<<"observation_pack_ready">>, TimelineTypes)),
  ?assert(lists:member(<<"reconsideration_package_created">>, TimelineTypes)),
  ?assert(lists:member(<<"reconsideration_package_deferred">>, TimelineTypes)),
  ?assert(lists:member(<<"reconsideration_package_superseded">>, TimelineTypes)),
  ?assert(lists:member(<<"reconsideration_round_started">>, TimelineTypes)),
  ok.

stale_deferred_reconsideration_package_cannot_start_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),
  PackId = create_pack_and_review(Root, CaseId, TaskIds),

  {ok, PackageRes} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  PackageId = id_of(maps:get(reconsideration_package, PackageRes)),

  {ok, _DeferredRes} =
    erlang:apply(
      openagentic_case_store,
      defer_reconsideration_package,
      [Root, #{case_id => CaseId, package_id => PackageId, acted_by_op_id => <<"lemon">>}]
    ),

  ok = expire_reports(Root, CaseId, TaskIds),

  ?assertMatch(
    {error, reconsideration_package_stale},
    erlang:apply(
      openagentic_case_store,
      start_reconsideration,
      [Root, #{case_id => CaseId, package_id => PackageId, started_by_op_id => <<"lemon">>}]
    )
  ).

min_report_count_pack_rule_can_override_all_required_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, [lists:nth(1, TaskIds)]),

  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Minimum reports pack">>,
          target_question => <<"Should one fresh report be enough to reopen deliberation?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400},
          completeness_rule => #{mode => <<"min_report_count">>, min_reports => 1},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  PackId = id_of(maps:get(pack, PackRes)),
  ?assertEqual(<<"awaiting_inspection">>, deep_get(maps:get(pack, PackRes), [state, status])),

  {ok, ReviewRes} =
    erlang:apply(
      openagentic_case_store,
      inspect_observation_pack,
      [Root, #{case_id => CaseId, pack_id => PackId, inspected_by_op_id => <<"lemon">>}]
    ),
  Review = maps:get(inspection_review, ReviewRes),
  assert_review_process_trace(Review, <<"ready_for_reconsideration">>),
  ?assertEqual(<<"ready_for_reconsideration">>, deep_get(Review, [state, status])).

inspection_rule_can_block_ready_when_blocking_issues_exist_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, [lists:nth(1, TaskIds)]),

  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Blocking issues gate pack">>,
          target_question => <<"Should blocking issues prevent reconsideration readiness?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400},
          completeness_rule => #{mode => <<"min_report_count">>, min_reports => 1},
          inspection_rule => #{mode => <<"require_no_blocking_issues">>},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  PackId = id_of(maps:get(pack, PackRes)),
  ?assertEqual(<<"awaiting_inspection">>, deep_get(maps:get(pack, PackRes), [state, status])),

  {ok, ReviewRes} =
    erlang:apply(
      openagentic_case_store,
      inspect_observation_pack,
      [Root, #{case_id => CaseId, pack_id => PackId, inspected_by_op_id => <<"lemon">>}]
    ),
  Review = maps:get(inspection_review, ReviewRes),
  assert_review_process_trace(Review, <<"insufficient">>),
  ?assertEqual(<<"insufficient">>, deep_get(Review, [state, status])).

manual_trigger_policy_keeps_package_creation_explicit_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),

  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Manual trigger policy pack">>,
          target_question => <<"Should ready packs avoid auto package creation by default?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  ?assertEqual(<<"awaiting_inspection">>, deep_get(maps:get(pack, PackRes), [state, status])),
  ?assertEqual([], maps:get(reconsideration_packages, maps:get(overview, PackRes))).

urgent_reconsideration_package_includes_urgent_refs_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  [UrgentTaskId, NormalTaskId] = TaskIds,
  {ok, _} =
    openagentic_case_store:run_task(
      Root,
      #{case_id => CaseId, task_id => UrgentTaskId, runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_urgent}}
    ),
  {ok, _} =
    openagentic_case_store:run_task(
      Root,
      #{case_id => CaseId, task_id => NormalTaskId, runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}}
    ),
  PackId = create_pack_and_review(Root, CaseId, TaskIds),

  {ok, PackageRes} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  Package = maps:get(reconsideration_package, PackageRes),
  UrgentRefs = deep_get(Package, [spec, included_urgent_refs]),

  ?assert(length(UrgentRefs) >= 1),
  ?assert(lists:any(fun (Ref) -> maps:get(type, Ref, undefined) =:= <<"urgent_brief">> end, UrgentRefs)).

inspect_observation_pack_revision_conflict_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),
  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Iran readiness pack">>,
          target_question => <<"Should the court reopen the Iran case?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  PackId = id_of(maps:get(pack, PackRes)),
  ?assertMatch(
    {error, {revision_conflict, _}},
    erlang:apply(
      openagentic_case_store,
      inspect_observation_pack,
      [Root, #{case_id => CaseId, pack_id => PackId, current_revision => 0, inspected_by_op_id => <<"lemon">>}]
    )
  ).

reconsideration_actions_revision_conflict_test() ->
  Root = tmp_root(),
  {CaseId, TaskIds} = create_two_active_tasks_fixture(Root),
  ok = run_tasks_successfully(Root, CaseId, TaskIds),
  PackId = create_pack_and_review(Root, CaseId, TaskIds),

  ?assertMatch(
    {error, {revision_conflict, _}},
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, current_revision => 0, created_by_op_id => <<"lemon">>}]
    )
  ),

  {ok, PackageRes} =
    erlang:apply(
      openagentic_case_store,
      create_reconsideration_package,
      [Root, #{case_id => CaseId, pack_id => PackId, created_by_op_id => <<"lemon">>}]
    ),
  PackageId = id_of(maps:get(reconsideration_package, PackageRes)),

  ?assertMatch(
    {error, {revision_conflict, _}},
    erlang:apply(
      openagentic_case_store,
      defer_reconsideration_package,
      [Root, #{case_id => CaseId, package_id => PackageId, current_revision => 0, acted_by_op_id => <<"lemon">>}]
    )
  ).

operation_partial_and_failed_states_test() ->
  Root = tmp_root(),
  {CaseId, _RoundId, _Sid} = create_case_fixture(Root),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  Now = openagentic_case_store_common_meta:now_ts(),
  Partial0 = openagentic_case_store_ops:new_operation(CaseId, <<"demo_partial">>, #{acted_by_op_id => <<"lemon">>}, Now),
  Partial = openagentic_case_store_ops:mark_partially_applied(Partial0, [#{type => <<"observation_pack">>, id => <<"pack_demo">>}], [<<"persist_pending_review">>], [<<"refresh_case_state">>], Now),
  ok = openagentic_case_store_ops:persist_operation(CaseDir, Partial),
  PartialStored = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:operation_file(CaseDir, id_of(Partial))),
  Failed0 = openagentic_case_store_ops:new_operation(CaseId, <<"demo_failed">>, #{acted_by_op_id => <<"lemon">>}, Now),
  Failed = openagentic_case_store_ops:mark_failed(Failed0, [#{type => <<"reconsideration_package">>, id => <<"pkg_demo">>}], [<<"update_package">>], Now),
  ok = openagentic_case_store_ops:persist_operation(CaseDir, Failed),
  FailedStored = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:operation_file(CaseDir, id_of(Failed))),

  ?assertEqual(<<"partially_applied">>, deep_get(PartialStored, [state, status])),
  ?assertEqual([<<"persist_pending_review">>], deep_get(PartialStored, [state, applied_steps])),
  ?assertEqual([<<"refresh_case_state">>], deep_get(PartialStored, [state, failed_steps])),
  ?assertEqual(<<"failed">>, deep_get(FailedStored, [state, status])),
  ?assertEqual([], deep_get(FailedStored, [state, applied_steps])),
  ?assertEqual([<<"update_package">>], deep_get(FailedStored, [state, failed_steps])).

assert_review_process_trace(Review, FinalStatus) ->
  History = deep_get(Review, [ext, status_history]),
  Statuses = [maps:get(status, Entry, undefined) || Entry <- History],
  ?assert(length(History) >= 3),
  ?assertEqual(<<"pending">>, hd(Statuses)),
  ?assert(lists:member(<<"reviewing">>, Statuses)),
  ?assertEqual(FinalStatus, lists:last(Statuses)).

create_two_active_tasks_fixture(Root) ->
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  Candidates = maps:get(candidates, Extracted),
  TaskIds =
    [
      begin
        {ok, Approved} =
          openagentic_case_store:approve_candidate(
            Root,
            #{
              case_id => CaseId,
              candidate_id => id_of(Candidate),
              approved_by_op_id => <<"lemon">>,
              approval_summary => <<"approve for monitoring execution">>,
              objective => <<"Track signals relevant to reconsideration readiness">>
            }
          ),
        id_of(maps:get(task, Approved))
      end
     || Candidate <- Candidates
    ],
  {CaseId, TaskIds}.

run_tasks_successfully(_Root, _CaseId, []) ->
  ok;
run_tasks_successfully(Root, CaseId, [TaskId | Rest]) ->
  {ok, _} =
    openagentic_case_store:run_task(
      Root,
      #{case_id => CaseId, task_id => TaskId, runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}}
    ),
  run_tasks_successfully(Root, CaseId, Rest).

create_pack_and_review(Root, CaseId, TaskIds) ->
  {ok, PackRes} =
    erlang:apply(
      openagentic_case_store,
      create_observation_pack,
      [
        Root,
        #{
          case_id => CaseId,
          title => <<"Iran readiness pack">>,
          target_question => <<"Should the court reopen the Iran case?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400},
          trigger_policy => #{mode => <<"manual">>}
        }
      ]
    ),
  PackId = id_of(maps:get(pack, PackRes)),
  {ok, _} =
    erlang:apply(
      openagentic_case_store,
      inspect_observation_pack,
      [Root, #{case_id => CaseId, pack_id => PackId, inspected_by_op_id => <<"lemon">>}]
    ),
  PackId.

expire_reports(Root, CaseId, TaskIds) ->
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  lists:foreach(
    fun (TaskId) ->
      Reports = openagentic_case_store_repo_readers:read_task_fact_reports(CaseDir, TaskId),
      Report = lists:last(Reports),
      Report1 =
        openagentic_case_store_repo_persist:update_object(
          Report,
          0,
          fun (Obj) -> Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{submitted_at => 0})} end
        ),
      ok =
        openagentic_case_store_repo_persist:persist_case_object(
          CaseDir,
          openagentic_case_store_repo_paths:fact_report_file(CaseDir, TaskId, id_of(Report)),
          Report1
        )
    end,
    TaskIds
  ).
