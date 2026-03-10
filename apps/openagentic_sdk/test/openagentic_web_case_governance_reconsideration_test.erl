-module(openagentic_web_case_governance_reconsideration_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_web_case_governance_test_support, [
  append_round_result/3,
  reset_web_runtime/0,
  ensure_httpc_started/0,
  http_post_json/2,
  http_get_json/1,
  deep_get_bin/2,
  tmp_root/0,
  pick_port/0,
  ensure_list/1,
  to_bin/1
]).

reconsideration_preview_and_actions_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{
          workflow_session_id => to_bin(Sid),
          title => <<"Iran Situation">>,
          opening_brief => <<"Create a long-running governance case around Iran">>,
          current_summary => <<"Deliberation completed; waiting for candidate extraction">>
        }
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    TaskIds = approve_all_candidates(Base, CaseId, [Candidate]),
    run_all_tasks(Base, CaseId, TaskIds),

    {201, PackCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs",
        #{
          created_by_op_id => <<"lemon">>,
          title => <<"Iran readiness pack">>,
          target_question => <<"Should the court reopen Iran deliberation?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400}
        }
      ),
    PackId = deep_get_bin(maps:get(<<"pack">>, PackCreated), [<<"header">>, <<"id">>]),

    {201, ReviewCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/inspect",
        #{inspected_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"ready_for_reconsideration">>, deep_get_bin(maps:get(<<"inspection_review">>, ReviewCreated), [<<"state">>, <<"status">>])),
    ReviewHistory = maps:get(<<"status_history">>, maps:get(<<"ext">>, maps:get(<<"inspection_review">>, ReviewCreated), #{}), []),
    ?assert(length(ReviewHistory) >= 3),
    ?assertEqual(<<"pending">>, deep_get_bin(hd(ReviewHistory), [<<"status">>])),
    ?assert(lists:member(<<"reviewing">>, [deep_get_bin(Item, [<<"status">>]) || Item <- ReviewHistory])),
    ?assertEqual(<<"ready_for_reconsideration">>, deep_get_bin(lists:last(ReviewHistory), [<<"status">>])),

    {201, PackageCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>}
      ),
    PackageId = deep_get_bin(maps:get(<<"reconsideration_package">>, PackageCreated), [<<"header">>, <<"id">>]),
    ?assertEqual(1, maps:get(<<"version_no">>, maps:get(<<"state">>, maps:get(<<"reconsideration_package">>, PackageCreated), #{}), 0)),
    ?assertEqual(<<"PACK-", PackId/binary, "-V1">>, deep_get_bin(maps:get(<<"reconsideration_package">>, PackageCreated), [<<"state">>, <<"display_code">>])),
    ?assertEqual(<<"reconsideration_ready">>, deep_get_bin(maps:get(<<"mail">>, PackageCreated), [<<"spec">>, <<"message_type">>])),
    ?assertEqual(PackageId, deep_get_bin(maps:get(<<"inspection_review">>, PackageCreated), [<<"links">>, <<"derived_briefing_id">>])),

    {200, Preview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/preview"),
    ?assertEqual(PackageId, deep_get_bin(maps:get(<<"reconsideration_package">>, Preview), [<<"header">>, <<"id">>])),
    ?assertEqual(<<"PACK-", PackId/binary, "-V1">>, deep_get_bin(maps:get(<<"reconsideration_session_context">>, Preview), [<<"package_display_code">>])),
    ?assert(is_map(maps:get(<<"based_on_round">>, maps:get(<<"preview">>, Preview)))),
    ?assert(length(maps:get(<<"baseline_facts">>, maps:get(<<"preview">>, Preview))) >= 1),
    ?assert(length(maps:get(<<"change_facts">>, maps:get(<<"preview">>, Preview))) >= 1),
    ?assertEqual(1, length(maps:get(<<"reports">>, maps:get(<<"preview">>, Preview)))),

    {200, Deferred} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/defer",
        #{acted_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"deferred">>, deep_get_bin(maps:get(<<"reconsideration_package">>, Deferred), [<<"state">>, <<"status">>])),
    {200, DeferredPreview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/preview"),
    ?assertEqual(<<"deferred">>, deep_get_bin(maps:get(<<"reconsideration_package">>, DeferredPreview), [<<"state">>, <<"status">>])),

    {201, PackageCreated2} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>}
      ),
    PackageId2 = deep_get_bin(maps:get(<<"reconsideration_package">>, PackageCreated2), [<<"header">>, <<"id">>]),

    {409, SupersededStart} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/start",
        #{started_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"reconsideration_package_superseded">>, maps:get(<<"error">>, SupersededStart)),
    {200, SupersededPreview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/preview"),
    ?assertEqual(<<"superseded">>, deep_get_bin(maps:get(<<"reconsideration_package">>, SupersededPreview), [<<"state">>, <<"status">>])),

    {200, Started} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId2) ++ "/start",
        #{started_by_op_id => <<"lemon">>}
      ),
    ?assert(deep_get_bin(maps:get(<<"round">>, Started), [<<"links">>, <<"workflow_session_id">>]) =/= <<>>),
    ?assertEqual(<<"consumed_by_round">>, deep_get_bin(maps:get(<<"reconsideration_package">>, Started), [<<"state">>, <<"status">>])),
    {200, ConsumedPreview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId2) ++ "/preview"),
    ?assertEqual(<<"consumed_by_round">>, deep_get_bin(maps:get(<<"reconsideration_package">>, ConsumedPreview), [<<"state">>, <<"status">>])),

    {200, Overview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/overview"),
    ?assertEqual(1, length(maps:get(<<"observation_packs">>, Overview))),
    ?assertEqual(1, length(maps:get(<<"inspection_reviews">>, Overview))),
    ?assertEqual(2, length(maps:get(<<"reconsideration_packages">>, Overview))),
    ?assertEqual(<<"reconsideration_in_progress">>, deep_get_bin(maps:get(<<"case">>, Overview), [<<"state">>, <<"phase">>])),

    CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
    ReviewIndex = openagentic_case_store_repo_persist:read_json(filename:join([CaseDir, "meta", "indexes", "inspection-reviews-by-status.json"])),
    PackageIndex = openagentic_case_store_repo_persist:read_json(filename:join([CaseDir, "meta", "indexes", "reconsideration-packages-by-status.json"])),
    ?assert(lists:member(deep_get_bin(maps:get(<<"inspection_review">>, ReviewCreated), [<<"header">>, <<"id">>]), maps:get(ready_for_reconsideration, ReviewIndex, []))),
    ?assert(lists:member(PackageId, maps:get(superseded, PackageIndex, []))),
    ?assert(lists:member(PackageId2, maps:get(consumed_by_round, PackageIndex, [])))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

stale_deferred_reconsideration_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{
          workflow_session_id => to_bin(Sid),
          title => <<"Iran Situation">>,
          opening_brief => <<"Create a long-running governance case around Iran">>,
          current_summary => <<"Deliberation completed; waiting for candidate extraction">>
        }
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    TaskIds = approve_all_candidates(Base, CaseId, [Candidate]),
    run_all_tasks(Base, CaseId, TaskIds),

    {201, PackCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs",
        #{
          created_by_op_id => <<"lemon">>,
          title => <<"Iran readiness pack">>,
          target_question => <<"Should the court reopen Iran deliberation?">>,
          task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds],
          freshness_window => #{max_age_seconds => 86400}
        }
      ),
    PackId = deep_get_bin(maps:get(<<"pack">>, PackCreated), [<<"header">>, <<"id">>]),

    {201, _ReviewCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/inspect",
        #{inspected_by_op_id => <<"lemon">>}
      ),

    {201, PackageCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>}
      ),
    PackageId = deep_get_bin(maps:get(<<"reconsideration_package">>, PackageCreated), [<<"header">>, <<"id">>]),

    {200, _Deferred} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/defer",
        #{acted_by_op_id => <<"lemon">>}
      ),

    ok = expire_reports(Root, CaseId, TaskIds),

    {409, StaleStart} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/start",
        #{started_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"reconsideration_package_stale">>, maps:get(<<"error">>, StaleStart))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

urgent_reconsideration_package_api_includes_urgent_refs_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{workflow_session_id => to_bin(Sid), title => <<"Iran Situation">>, opening_brief => <<"Create a long-running governance case around Iran">>, current_summary => <<"Deliberation completed; waiting for candidate extraction">>}
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate1, Candidate2 | _] = maps:get(<<"candidates">>, Created),
    [UrgentTaskId, NormalTaskId] = approve_all_candidates(Base, CaseId, [Candidate1, Candidate2]),
    {201, _} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(UrgentTaskId) ++ "/run",
        #{runtime_opts => #{provider_mod => <<"openagentic_testing_provider_monitoring_urgent">>}}
      ),
    {201, _} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(NormalTaskId) ++ "/run",
        #{runtime_opts => #{provider_mod => <<"openagentic_testing_provider_monitoring_success">>}}
      ),

    {201, PackCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs",
        #{created_by_op_id => <<"lemon">>, title => <<"Iran readiness pack">>, target_question => <<"Should the court reopen Iran deliberation?">>, task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- [UrgentTaskId, NormalTaskId]], freshness_window => #{max_age_seconds => 86400}}
      ),
    PackId = deep_get_bin(maps:get(<<"pack">>, PackCreated), [<<"header">>, <<"id">>]),

    {201, _ReviewCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/inspect",
        #{inspected_by_op_id => <<"lemon">>}
      ),

    {201, PackageCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>}
      ),
    UrgentRefs = maps:get(<<"included_urgent_refs">>, maps:get(<<"spec">>, maps:get(<<"reconsideration_package">>, PackageCreated), #{}), []),
    ?assert(length(UrgentRefs) >= 1)
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

inspect_revision_conflict_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items
",
          "- Monitor Iran diplomatic statement frequency and wording shifts
",
          "- Track US sanctions policy and enforcement cadence
">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{workflow_session_id => to_bin(Sid), title => <<"Iran Situation">>, opening_brief => <<"Create a long-running governance case around Iran">>, current_summary => <<"Deliberation completed; waiting for candidate extraction">>}
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    TaskIds = approve_all_candidates(Base, CaseId, [Candidate]),
    run_all_tasks(Base, CaseId, TaskIds),

    {201, PackCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs",
        #{created_by_op_id => <<"lemon">>, title => <<"Iran readiness pack">>, target_question => <<"Should the court reopen Iran deliberation?">>, task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds], freshness_window => #{max_age_seconds => 86400}}
      ),
    PackId = deep_get_bin(maps:get(<<"pack">>, PackCreated), [<<"header">>, <<"id">>]),

    {409, InspectConflict} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/inspect",
        #{inspected_by_op_id => <<"lemon">>, current_revision => 0}
      ),
    ?assertEqual(<<"revision_conflict">>, maps:get(<<"error">>, InspectConflict))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

reconsideration_revision_conflict_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{workflow_session_id => to_bin(Sid), title => <<"Iran Situation">>, opening_brief => <<"Create a long-running governance case around Iran">>, current_summary => <<"Deliberation completed; waiting for candidate extraction">>}
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    TaskIds = approve_all_candidates(Base, CaseId, [Candidate]),
    run_all_tasks(Base, CaseId, TaskIds),

    {201, PackCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs",
        #{created_by_op_id => <<"lemon">>, title => <<"Iran readiness pack">>, target_question => <<"Should the court reopen Iran deliberation?">>, task_bindings => [#{task_id => TaskId, role => <<"required">>, required => true} || TaskId <- TaskIds], freshness_window => #{max_age_seconds => 86400}}
      ),
    PackId = deep_get_bin(maps:get(<<"pack">>, PackCreated), [<<"header">>, <<"id">>]),

    {201, _ReviewCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/inspect",
        #{inspected_by_op_id => <<"lemon">>}
      ),

    {409, CreateConflict} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>, current_revision => 0}
      ),
    ?assertEqual(<<"revision_conflict">>, maps:get(<<"error">>, CreateConflict)),

    {201, PackageCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/observation-packs/" ++ ensure_list(PackId) ++ "/reconsideration-packages",
        #{created_by_op_id => <<"lemon">>}
      ),
    PackageId = deep_get_bin(maps:get(<<"reconsideration_package">>, PackageCreated), [<<"header">>, <<"id">>]),

    {409, StartConflict} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/reconsideration-packages/" ++ ensure_list(PackageId) ++ "/start",
        #{started_by_op_id => <<"lemon">>, current_revision => 0}
      ),
    ?assertEqual(<<"revision_conflict">>, maps:get(<<"error">>, StartConflict))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

approve_all_candidates(_Base, _CaseId, []) ->
  [];
approve_all_candidates(Base, CaseId, [Candidate | Rest]) ->
  CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),
  {201, Approved} =
    http_post_json(
      Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
      #{
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"Approve as monitoring task">>,
        objective => <<"Track reconsideration signals">>
      }
    ),
  [deep_get_bin(maps:get(<<"task">>, Approved), [<<"header">>, <<"id">>]) | approve_all_candidates(Base, CaseId, Rest)].

run_all_tasks(_Base, _CaseId, []) ->
  ok;
run_all_tasks(Base, CaseId, [TaskId | Rest]) ->
  {201, _} =
    http_post_json(
      Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/run",
      #{runtime_opts => #{provider_mod => <<"openagentic_testing_provider_monitoring_success">>}}
    ),
  run_all_tasks(Base, CaseId, Rest).

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
          openagentic_case_store_repo_paths:fact_report_file(CaseDir, TaskId, deep_get_bin(Report, [header, id])),
          Report1
        )
    end,
    TaskIds
  ).
