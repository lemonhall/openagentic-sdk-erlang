-module(openagentic_case_store_api_reconsideration).

-export([
  create_observation_pack/2,
  inspect_observation_pack/2,
  create_reconsideration_package/2,
  get_reconsideration_preview/3,
  defer_reconsideration_package/2,
  start_reconsideration/2
]).

create_observation_pack(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      Now = openagentic_case_store_common_meta:now_ts(),
      PackId = openagentic_case_store_common_lookup:get_bin(Input, [pack_id, packId], openagentic_case_store_common_meta:new_id(<<"pack">>)),
      FreshnessWindow = openagentic_case_store_common_lookup:choose_map(Input, [freshness_window, freshnessWindow], #{max_age_seconds => 86400}),
      CompletenessRule = openagentic_case_store_common_lookup:choose_map(Input, [completeness_rule, completenessRule], #{mode => <<"all_required_reports_present">>}),
      InspectionRule = openagentic_case_store_common_lookup:choose_map(Input, [inspection_rule, inspectionRule], #{mode => <<"manual_inspection_required">>}),
      TriggerPolicy = openagentic_case_store_common_lookup:choose_map(Input, [trigger_policy, triggerPolicy], #{mode => <<"manual">>}),
      TaskBindings = normalize_task_bindings(CaseDir, Input, FreshnessWindow),
      Eval = evaluate_pack(CaseDir, TaskBindings, FreshnessWindow, Now),
      Pack =
        #{
          header => openagentic_case_store_common_meta:header(PackId, <<"observation_pack">>, Now),
          links =>
            openagentic_case_store_common_meta:compact_map(
              #{
                case_id => CaseId,
                source_round_id => openagentic_case_store_common_lookup:get_in_map(CaseObj, [links, current_round_id], undefined),
                latest_briefing_id => undefined,
                current_inspection_review_id => undefined
              }
            ),
          spec =>
            openagentic_case_store_common_meta:compact_map(
              #{
                title => openagentic_case_store_common_lookup:get_bin(Input, [title], <<"Observation Pack">>),
                target_question => openagentic_case_store_common_lookup:get_bin(Input, [target_question, targetQuestion], <<"Should the court reopen deliberation?">>),
                task_bindings => TaskBindings,
                freshness_window => FreshnessWindow,
                completeness_rule => CompletenessRule,
                inspection_rule => InspectionRule,
                trigger_policy => TriggerPolicy
              }
            ),
          state => pack_state(Eval, CompletenessRule, undefined),
          audit => openagentic_case_store_common_meta:compact_map(#{created_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [created_by_op_id, createdByOpId], undefined)}),
          ext => #{latest_report_ids => maps:get(report_ids, Eval), latest_run_ids => maps:get(run_ids, Eval)}
        },
      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:observation_pack_file(CaseDir, PackId), Pack),
      ok = bind_pack_to_tasks(CaseDir, PackId, TaskBindings, Now),
      ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
      ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
      {ok, #{pack => Pack, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}
  end.

inspect_observation_pack(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  PackId = openagentic_case_store_common_lookup:required_bin(Input, [pack_id, packId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      case load_pack(CaseDir, PackId) of
        {error, Reason} -> {error, Reason};
        {ok, Pack0} ->
          case require_revision(Pack0, Input) of
            ok ->
              Now = openagentic_case_store_common_meta:now_ts(),
              Operation0 = openagentic_case_store_ops:new_operation(CaseId, <<"inspect_observation_pack">>, Input, Now),
              PackSpec = pack_spec(Pack0),
              FreshnessWindow = openagentic_case_store_common_lookup:choose_map(PackSpec, [freshness_window], #{max_age_seconds => 86400}),
              TaskBindings = openagentic_case_store_common_lookup:get_in_map(PackSpec, [task_bindings], []),
              CompletenessRule = openagentic_case_store_common_lookup:choose_map(PackSpec, [completeness_rule], #{mode => <<"all_required_reports_present">>}),
              InspectionRule = openagentic_case_store_common_lookup:choose_map(PackSpec, [inspection_rule], #{mode => <<"manual_inspection_required">>}),
              TriggerPolicy = openagentic_case_store_common_lookup:choose_map(PackSpec, [trigger_policy], #{mode => <<"manual">>}),
              Eval = evaluate_pack(CaseDir, TaskBindings, FreshnessWindow, Now),
              ReviewId = openagentic_case_store_common_meta:new_id(<<"review">>),
              Controversies = review_controversies(Eval),
              Completeness = openagentic_case_store_reconsideration_rules:evaluate_completeness_rule(Eval, CompletenessRule, Now),
              ReviewRule = openagentic_case_store_reconsideration_rules:evaluate_inspection_rule(#{completeness => Completeness, controversies => Controversies, blocking_issues => maps:get(missing_requirements, Eval)}, InspectionRule),
              ReviewStatus = maps:get(status, ReviewRule),
              Review0 = new_pending_review(CaseId, PackId, ReviewId, Pack0, Eval, FreshnessWindow, CompletenessRule, InspectionRule, TriggerPolicy, Input, Now),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:inspection_review_file(CaseDir, ReviewId), Review0),
              Review1 = mark_reviewing(Review0, Now),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:inspection_review_file(CaseDir, ReviewId), Review1),
              Review = finalize_review(Review1, ReviewStatus, Controversies, Eval, Now),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:inspection_review_file(CaseDir, ReviewId), Review),
              Pack = openagentic_case_store_repo_persist:update_object(Pack0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{current_inspection_review_id => ReviewId}), state => maps:merge(maps:get(state, Obj, #{}), pack_state(Eval, CompletenessRule, ReviewStatus))} end),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:observation_pack_file(CaseDir, PackId), Pack),
              ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
              ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
              ok = openagentic_case_store_timeline:append_best_effort(CaseDir, openagentic_case_store_timeline:new_event(CaseId, case ReviewStatus of <<"ready_for_reconsideration">> -> <<"observation_pack_ready">>; _ -> <<"observation_pack_inspected">> end, <<"observation pack inspection completed">>, [#{type => <<"observation_pack">>, id => PackId}, #{type => <<"inspection_review">>, id => ReviewId}], object_id(Operation0), Now)),
              Operation = openagentic_case_store_ops:mark_applied(Operation0, [#{type => <<"observation_pack">>, id => PackId}, #{type => <<"inspection_review">>, id => ReviewId}], [<<"persist_pending_review">>, <<"finalize_review">>, <<"update_pack">>, <<"refresh_case_state">>, <<"rebuild_indexes">>], Now),
              ok = openagentic_case_store_ops:persist_operation(CaseDir, Operation),
              {ok, #{pack => Pack, inspection_review => Review, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}};
            Error -> Error
          end
      end
  end.

create_reconsideration_package(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  PackId = openagentic_case_store_common_lookup:required_bin(Input, [pack_id, packId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj, CaseDir} ->
      case load_pack(CaseDir, PackId) of
        {error, Reason} -> {error, Reason};
        {ok, Pack} ->
          case require_revision(Pack, Input) of
            ok ->
              ReviewId = openagentic_case_store_common_lookup:get_in_map(Pack, [links, current_inspection_review_id], undefined),
              case load_review(CaseDir, ReviewId) of
                {error, Reason} -> {error, Reason};
                {ok, Review} ->
                  case openagentic_case_store_common_lookup:get_in_map(Review, [state, status], <<>>) of
                    <<"ready_for_reconsideration">> -> create_reconsideration_package_ready(RootDir, CaseId, CaseObj, CaseDir, Pack, Review, Input);
                    _ -> {error, inspection_not_ready}
                  end
              end;
            {error, _} = Err -> Err
          end
      end
  end.

get_reconsideration_preview(RootDir0, CaseId0, PackageId0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  CaseId = openagentic_case_store_common_core:to_bin(CaseId0),
  PackageId = openagentic_case_store_common_core:to_bin(PackageId0),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      case load_package(CaseDir, PackageId) of
        {error, Reason} -> {error, Reason};
        {ok, Package} -> {ok, #{reconsideration_package => Package, reconsideration_session_context => reconsideration_session_context(Package), preview => maps:get(frozen_payload, maps:get(ext, Package, #{}), #{})}}
      end
  end.

defer_reconsideration_package(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  PackageId = openagentic_case_store_common_lookup:required_bin(Input, [package_id, packageId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      case load_package(CaseDir, PackageId) of
        {error, Reason} -> {error, Reason};
        {ok, Package0} ->
          case require_revision(Package0, Input) of
            ok ->
              Now = openagentic_case_store_common_meta:now_ts(),
              Operation0 = openagentic_case_store_ops:new_operation(CaseId, <<"defer_reconsideration_package">>, Input, Now),
              Package = openagentic_case_store_repo_persist:update_object(Package0, Now, fun (Obj) -> Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"deferred">>})} end),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PackageId), Package),
              maybe_mark_pack_deferred(CaseDir, Package, Now),
              ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
              ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
              ok = openagentic_case_store_timeline:append_best_effort(CaseDir, openagentic_case_store_timeline:new_event(CaseId, <<"reconsideration_package_deferred">>, <<"reconsideration package deferred">>, [#{type => <<"reconsideration_package">>, id => PackageId}], object_id(Operation0), Now)),
              Operation = openagentic_case_store_ops:mark_applied(Operation0, [#{type => <<"reconsideration_package">>, id => PackageId}], [<<"update_package">>, <<"mark_pack_deferred">>, <<"refresh_case_state">>, <<"rebuild_indexes">>], Now),
              ok = openagentic_case_store_ops:persist_operation(CaseDir, Operation),
              {ok, #{reconsideration_package => Package, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}};
            {error, _} = Err -> Err
          end
      end
  end.

start_reconsideration(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  PackageId = openagentic_case_store_common_lookup:required_bin(Input, [package_id, packageId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseObj0, CaseDir} ->
      case load_package(CaseDir, PackageId) of
        {error, Reason} -> {error, Reason};
        {ok, Package0} ->
          case require_revision(Package0, Input) of
            ok ->
              GateNow = openagentic_case_store_common_meta:now_ts(),
              case start_reconsideration_gate(CaseDir, Package0, GateNow) of
                {error, Reason} -> {error, Reason};
                ok ->
                  Now = openagentic_case_store_common_meta:now_ts(),
                  Operation0 = openagentic_case_store_ops:new_operation(CaseId, <<"start_reconsideration">>, Input, Now),
                  SessionContext = reconsideration_session_context(Package0),
                  {ok, WorkflowSessionId} = openagentic_session_store:create_session(RootDir, #{reconsideration_context => SessionContext}),
                  WorkflowSessionIdBin = openagentic_case_store_common_core:to_bin(WorkflowSessionId),
                  {ok, _} = openagentic_session_store:append_event(RootDir, WorkflowSessionId, openagentic_events:system_init(WorkflowSessionIdBin, openagentic_case_store_common_core:to_bin(RootDir), #{reconsideration_context => SessionContext})),
                  RoundId = openagentic_case_store_common_meta:new_id(<<"round">>),
                  Round = #{header => openagentic_case_store_common_meta:header(RoundId, <<"deliberation_round">>, Now), links => #{case_id => CaseId, parent_round_id => openagentic_case_store_common_lookup:get_in_map(CaseObj0, [links, current_round_id], undefined), workflow_session_id => WorkflowSessionId, reconsideration_package_id => PackageId, triggering_briefing_id => PackageId}, spec => #{round_index => next_round_index(CaseDir), kind => <<"reconsideration">>, trigger_reason => openagentic_case_store_common_lookup:get_in_map(Package0, [spec, trigger_reason], <<"reconsideration_package_consumed">>), starter_role => <<"court">>, input_material_refs => [#{type => <<"reconsideration_package">>, id => PackageId}]}, state => #{status => <<"created">>, phase => <<"queued">>, started_at => Now}, audit => openagentic_case_store_common_meta:compact_map(#{started_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [started_by_op_id, startedByOpId], undefined)}), ext => #{}},
                  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:round_file(CaseDir, RoundId), Round),
                  Package = openagentic_case_store_repo_persist:update_object(Package0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{consumed_by_round_id => RoundId}), state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"consumed_by_round">>})} end),
                  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PackageId), Package),
                  CaseObj = openagentic_case_store_repo_persist:update_object(CaseObj0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{current_round_id => RoundId, latest_briefing_id => PackageId}), state => maps:merge(maps:get(state, Obj, #{}), #{phase => <<"reconsideration_in_progress">>})} end),
                  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:case_file(CaseDir), CaseObj),
                  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
                  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
                  ok = openagentic_case_store_timeline:append_best_effort(CaseDir, openagentic_case_store_timeline:new_event(CaseId, <<"reconsideration_round_started">>, <<"reconsideration round started">>, [#{type => <<"reconsideration_package">>, id => PackageId}, #{type => <<"deliberation_round">>, id => RoundId}], object_id(Operation0), Now)),
                  Operation = openagentic_case_store_ops:mark_applied(Operation0, [#{type => <<"reconsideration_package">>, id => PackageId}, #{type => <<"deliberation_round">>, id => RoundId}], [<<"create_session">>, <<"persist_round">>, <<"consume_package">>, <<"update_case">>, <<"refresh_case_state">>, <<"rebuild_indexes">>], Now),
                  ok = openagentic_case_store_ops:persist_operation(CaseDir, Operation),
                  {ok, #{round => Round, reconsideration_package => Package, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}
              end;
            {error, _} = Err -> Err
          end
      end
  end.

create_reconsideration_package_ready(RootDir, CaseId, CaseObj, CaseDir, Pack0, Review, Input) ->
  Now = openagentic_case_store_common_meta:now_ts(),
  Operation0 = openagentic_case_store_ops:new_operation(CaseId, <<"create_reconsideration_package">>, Input, Now),
  PackageId = openagentic_case_store_common_meta:new_id(<<"package">>),
  PackId = openagentic_case_store_common_meta:id_of(Pack0),
  PackVersion = next_pack_version(CaseDir, PackId),
  ReportIds = openagentic_case_store_common_lookup:get_in_map(Review, [links, reviewed_report_ids], []),
  ReportObjs = [load_report(CaseDir, ReportId) || ReportId <- ReportIds],
  IncludedUrgentRefs = openagentic_case_store_run_urgent_brief:included_urgent_refs(ReportObjs),
  PreviousPackage = latest_live_package(CaseDir, PackId),
  ok = maybe_supersede_live_package(CaseDir, PreviousPackage, PackageId, Now),
  FrozenPayload = frozen_payload(RootDir, CaseDir, CaseObj, Pack0, Review, ReportObjs),
  Package = #{header => openagentic_case_store_common_meta:header(PackageId, <<"reconsideration_package">>, Now), links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, pack_id => PackId, pack_version => PackVersion, based_on_round_id => openagentic_case_store_common_lookup:get_in_map(Pack0, [links, source_round_id], undefined), source_inspection_review_id => openagentic_case_store_common_meta:id_of(Review), supersedes_briefing_id => object_id(PreviousPackage), consumed_by_round_id => undefined}), spec => #{trigger_reason => <<"inspection_completed">>, included_report_refs => [#{type => <<"fact_report">>, id => openagentic_case_store_common_meta:id_of(Report)} || Report <- ReportObjs], included_resolution_ref => case openagentic_case_store_common_lookup:get_in_map(CaseObj, [links, current_round_id], undefined) of undefined -> undefined; RoundId -> #{type => <<"deliberation_round">>, id => RoundId} end, included_urgent_refs => IncludedUrgentRefs, included_controversy_refs => [#{id => maps:get(id, Item, undefined), title => maps:get(title, Item, undefined)} || Item <- openagentic_case_store_common_lookup:get_in_map(Review, [spec, controversy_candidates], [])]}, state => #{status => <<"ready">>, freshness_checked_at => Now, stale_reason => undefined, version_no => PackVersion, display_code => reconsideration_display_code(PackId, PackVersion)}, audit => openagentic_case_store_common_meta:compact_map(#{issuer_role => <<"inspector">>, created_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [created_by_op_id, createdByOpId], undefined)}), ext => #{frozen_payload => FrozenPayload, preview_url => preview_url(CaseId, PackageId)}},
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PackageId), Package),
  Review1 = openagentic_case_store_repo_persist:update_object(Review, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{derived_briefing_id => PackageId})} end),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:inspection_review_file(CaseDir, openagentic_case_store_common_meta:id_of(Review)), Review1),
  Pack = openagentic_case_store_repo_persist:update_object(Pack0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{latest_briefing_id => PackageId}), state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"ready_for_reconsideration">>, latest_ready_at => Now})} end),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:observation_pack_file(CaseDir, openagentic_case_store_common_meta:id_of(Pack0)), Pack),
  Mail = ready_mail(CaseId, CaseObj, Pack, Review1, Package, FrozenPayload, object_id(Operation0), Now),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:mail_file(CaseDir, openagentic_case_store_common_meta:id_of(Mail)), Mail),
  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  ok =
    openagentic_case_store_timeline:append_best_effort(
      CaseDir,
      openagentic_case_store_timeline:new_event(
        CaseId,
        <<"reconsideration_package_created">>,
        <<"reconsideration package created">>,
        [#{type => <<"reconsideration_package">>, id => object_id(Package)}, #{type => <<"inspection_review">>, id => object_id(Review1)}],
        object_id(Operation0),
        Now
      )
    ),
  ok =
    case PreviousPackage of
      undefined -> ok;
      _ ->
        openagentic_case_store_timeline:append_best_effort(
          CaseDir,
          openagentic_case_store_timeline:new_event(
            CaseId,
            <<"reconsideration_package_superseded">>,
            <<"reconsideration package superseded">>,
            [#{type => <<"reconsideration_package">>, id => object_id(PreviousPackage)}, #{type => <<"reconsideration_package">>, id => object_id(Package)}],
            object_id(Operation0),
            Now
          )
        )
    end,
  Operation =
    openagentic_case_store_ops:mark_applied(
      Operation0,
      [
        #{type => <<"observation_pack">>, id => object_id(Pack)},
        #{type => <<"inspection_review">>, id => object_id(Review1)},
        #{type => <<"reconsideration_package">>, id => object_id(Package)},
        #{type => <<"internal_mail">>, id => object_id(Mail)}
      ],
      [<<"maybe_supersede_previous_package">>, <<"persist_package">>, <<"update_review_backlink">>, <<"update_pack">>, <<"persist_mail">>, <<"refresh_case_state">>, <<"rebuild_indexes">>],
      Now
    ),
  ok = openagentic_case_store_ops:persist_operation(CaseDir, Operation),
  {ok, #{pack => Pack, inspection_review => Review1, reconsideration_package => Package, mail => Mail, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}.

new_pending_review(CaseId, PackId, ReviewId, Pack0, Eval, FreshnessWindow, CompletenessRule, InspectionRule, TriggerPolicy, Input, Now) ->
  #{header => openagentic_case_store_common_meta:header(ReviewId, <<"inspection_review">>, Now), links => #{case_id => CaseId, pack_id => PackId, reviewed_run_ids => maps:get(run_ids, Eval), reviewed_report_ids => maps:get(report_ids, Eval), derived_briefing_id => undefined}, spec => #{review_scope => #{target_question => openagentic_case_store_common_lookup:get_in_map(Pack0, [spec, target_question], <<>>), report_count => length(maps:get(report_ids, Eval))}, checklist => [<<"freshness">>, <<"completeness">>], applied_rules => #{freshness_window => FreshnessWindow, completeness_rule => CompletenessRule, inspection_rule => InspectionRule, trigger_policy => TriggerPolicy}, controversy_candidates => []}, state => #{status => <<"pending">>, process_state => <<"pending">>, decision => <<"pending">>, blocking_issues => maps:get(missing_requirements, Eval), missing_items => maps:get(missing_requirements, Eval), quality_notes => report_summaries(maps:get(report_objs, Eval)), confidence_notes => []}, audit => openagentic_case_store_common_meta:compact_map(#{issuer_role => <<"inspector">>, inspected_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [inspected_by_op_id, inspectedByOpId], undefined)}), ext => #{status_history => [review_status_entry(<<"pending">>, Now)]}}.

mark_reviewing(Review0, Now) ->
  openagentic_case_store_repo_persist:update_object(Review0, Now, fun (Obj) -> Ext0 = maps:get(ext, Obj, #{}), StatusHistory0 = openagentic_case_store_common_lookup:get_in_map(Obj, [ext, status_history], []), Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"reviewing">>, process_state => <<"reviewing">>, decision => <<"pending">>}), ext => maps:merge(Ext0, #{status_history => StatusHistory0 ++ [review_status_entry(<<"reviewing">>, Now)]})} end).

finalize_review(Review0, ReviewStatus, Controversies, Eval, Now) ->
  openagentic_case_store_repo_persist:update_object(Review0, Now, fun (Obj) -> Ext0 = maps:get(ext, Obj, #{}), StatusHistory0 = openagentic_case_store_common_lookup:get_in_map(Obj, [ext, status_history], []), Obj#{spec => maps:merge(maps:get(spec, Obj, #{}), #{controversy_candidates => Controversies}), state => maps:merge(maps:get(state, Obj, #{}), #{status => ReviewStatus, process_state => <<"completed">>, decision => ReviewStatus, blocking_issues => maps:get(missing_requirements, Eval), missing_items => maps:get(missing_requirements, Eval), quality_notes => report_summaries(maps:get(report_objs, Eval)), confidence_notes => []}), ext => maps:merge(Ext0, #{status_history => StatusHistory0 ++ [review_status_entry(ReviewStatus, Now)]})} end).

review_status_entry(Status, Now) -> #{status => Status, at => Now}.

normalize_task_bindings(CaseDir, Input, FreshnessWindow) ->
  Bindings0 = openagentic_case_store_common_lookup:get_list(Input, [task_bindings, taskBindings], []),
  case Bindings0 of
    [] ->
      Tasks = openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
      [#{task_id => openagentic_case_store_common_meta:id_of(Task), role => <<"required">>, required => true, freshness_requirement => FreshnessWindow} || Task <- Tasks, openagentic_case_store_case_state:counts_as_live_task(openagentic_case_store_common_lookup:get_in_map(Task, [state, status], <<>>))];
    _ ->
      [#{task_id => openagentic_case_store_common_lookup:get_bin(Binding, [task_id, taskId], undefined), role => openagentic_case_store_common_lookup:get_bin(Binding, [role], <<"required">>), required => openagentic_case_store_common_lookup:get_bool(Binding, [required], true), freshness_requirement => openagentic_case_store_common_lookup:choose_map(Binding, [freshness_requirement, freshnessRequirement], FreshnessWindow)} || Binding <- Bindings0]
  end.

evaluate_pack(CaseDir, TaskBindings, FreshnessWindow, Now) ->
  lists:foldl(
    fun (Binding0, Acc0) ->
      Binding = openagentic_case_store_common_core:ensure_map(Binding0),
      TaskId = openagentic_case_store_common_lookup:get_bin(Binding, [task_id], <<>>),
      Required = openagentic_case_store_common_lookup:get_bool(Binding, [required], true),
      Report = latest_report(CaseDir, TaskId),
      Missing = missing_requirement(Report, Binding, FreshnessWindow, Now, Required),
      Acc1 = Acc0#{required_total => maps:get(required_total, Acc0) + case Required of true -> 1; false -> 0 end, report_ids => append_if_defined(object_id(Report), maps:get(report_ids, Acc0)), run_ids => append_if_defined(run_id(Report), maps:get(run_ids, Acc0)), report_objs => append_if_defined(Report, maps:get(report_objs, Acc0))},
      case Missing of
        undefined -> Acc1#{satisfied_required => maps:get(satisfied_required, Acc1) + case Required of true -> 1; false -> 0 end};
        _ -> Acc1#{missing_requirements => maps:get(missing_requirements, Acc1) ++ [maps:merge(#{task_id => TaskId, role => openagentic_case_store_common_lookup:get_bin(Binding, [role], <<"required">>)}, Missing)]}
      end
    end,
    #{required_total => 0, satisfied_required => 0, report_ids => [], run_ids => [], report_objs => [], missing_requirements => []},
    TaskBindings
  ).

missing_requirement(undefined, _Binding, _FreshnessWindow, _Now, true) -> #{reason => <<"missing_report">>, message => <<"required task has no fact report yet">>};
missing_requirement(undefined, _Binding, _FreshnessWindow, _Now, false) -> undefined;
missing_requirement(Report, Binding, FreshnessWindow, Now, true) ->
  Requirement = openagentic_case_store_common_lookup:choose_map(Binding, [freshness_requirement], FreshnessWindow),
  MaxAge = openagentic_case_store_common_lookup:get_number(Requirement, [max_age_seconds, maxAgeSeconds], undefined),
  SubmittedAt = openagentic_case_store_common_lookup:get_in_map(Report, [state, submitted_at], openagentic_case_store_common_lookup:get_in_map(Report, [header, updated_at], 0)),
  case is_number(MaxAge) andalso (Now - SubmittedAt > MaxAge) of
    true -> #{reason => <<"stale_report">>, message => <<"required report is outside freshness window">>, report_id => object_id(Report)};
    false -> undefined
  end;
missing_requirement(_Report, _Binding, _FreshnessWindow, _Now, false) -> undefined.

pack_state(Eval, CompletenessRule, OverrideStatus) ->
  RequiredTotal = maps:get(required_total, Eval),
  ReadyScore = case RequiredTotal of 0 -> 100; _ -> erlang:round((maps:get(satisfied_required, Eval) * 100) / RequiredTotal) end,
  Completeness = openagentic_case_store_reconsideration_rules:evaluate_completeness_rule(Eval, CompletenessRule, openagentic_case_store_common_meta:now_ts()),
  Status0 = maps:get(status, Completeness),
  #{status => case OverrideStatus of undefined -> Status0; _ -> OverrideStatus end, ready_score => ReadyScore, missing_requirements => maps:get(missing_requirements, Eval), latest_ready_at => maps:get(latest_ready_at, Completeness, undefined), latest_deferred_briefing_id => undefined}.

latest_report(CaseDir, TaskId) ->
  Reports = lists:reverse(openagentic_case_store_repo_readers:read_task_fact_reports(CaseDir, TaskId)),
  case Reports of [Report | _] -> Report; [] -> undefined end.

bind_pack_to_tasks(CaseDir, PackId, TaskBindings, Now) ->
  lists:foreach(
    fun (Binding0) ->
      TaskId = openagentic_case_store_common_lookup:get_bin(Binding0, [task_id], <<>>),
      Path = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(Path) of
        false -> ok;
        true ->
          Task0 = openagentic_case_store_repo_persist:read_json(Path),
          Existing = openagentic_case_store_common_lookup:get_in_map(Task0, [links, active_pack_ids], []),
          Task1 = openagentic_case_store_repo_persist:update_object(Task0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{active_pack_ids => lists:usort([PackId | Existing])})} end),
          ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, Path, Task1)
      end
    end,
    TaskBindings
  ),
  ok.

load_pack(CaseDir, PackId) -> load_object(openagentic_case_store_repo_paths:observation_pack_file(CaseDir, PackId)).
load_review(CaseDir, ReviewId) -> load_object(openagentic_case_store_repo_paths:inspection_review_file(CaseDir, ReviewId)).
load_package(CaseDir, PackageId) -> load_object(openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PackageId)).

load_object(Path) ->
  case filelib:is_file(Path) of
    true -> {ok, openagentic_case_store_repo_persist:read_json(Path)};
    false -> {error, not_found}
  end.

load_report(CaseDir, ReportId) ->
  TaskDirs = openagentic_case_store_repo_readers:safe_list_dir(filename:join([CaseDir, "meta", "tasks"])),
  load_report(TaskDirs, CaseDir, ReportId).

load_report([], _CaseDir, _ReportId) -> #{};
load_report([TaskDir | Rest], CaseDir, ReportId) ->
  Path = filename:join([CaseDir, "meta", "tasks", TaskDir, "reports", openagentic_case_store_common_core:ensure_list(ReportId) ++ ".json"]),
  case filelib:is_file(Path) of
    true -> openagentic_case_store_repo_persist:read_json(Path);
    false -> load_report(Rest, CaseDir, ReportId)
  end.

review_controversies(Eval) ->
  case maps:get(report_objs, Eval) of
    [Report | _] -> [#{id => openagentic_case_store_common_meta:new_id(<<"controversy">>), title => <<"Whether the latest monitoring checkpoint changes the prior assessment">>, summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], <<"The latest reports are complete and should be reviewed by the court.">>), question => <<"Does this completed observation pack justify reopening deliberation?">>, report_id => object_id(Report), delta_type => <<"checkpoint">>, severity => <<"normal">>}];
    [] -> [#{id => openagentic_case_store_common_meta:new_id(<<"controversy">>), title => <<"Whether the completed observation pack should trigger reconsideration">>, summary => <<"The pack is complete enough to prepare a formal brief.">>, question => <<"Does the court want to reopen deliberation now?">>, delta_type => <<"checkpoint">>, severity => <<"normal">>}]
  end.

report_summaries(Reports) -> [Summary || Report <- Reports, Summary <- [openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], undefined)], is_binary(Summary)].

latest_live_package(CaseDir, PackId) ->
  Packages =
    [
      Package
     || Package <- openagentic_case_store_repo_readers:read_reconsideration_packages(CaseDir),
        openagentic_case_store_common_lookup:get_in_map(Package, [links, pack_id], <<>>) =:= PackId,
        lists:member(openagentic_case_store_common_lookup:get_in_map(Package, [state, status], <<>>), [<<"ready">>, <<"deferred">>])
    ],
  case Packages of [] -> undefined; _ -> lists:last(Packages) end.

next_pack_version(CaseDir, PackId) ->
  Versions =
    [
      package_version_no(Package)
     || Package <- openagentic_case_store_repo_readers:read_reconsideration_packages(CaseDir),
        openagentic_case_store_common_lookup:get_in_map(Package, [links, pack_id], <<>>) =:= PackId
    ],
  lists:max([0 | Versions]) + 1.

package_version_no(Package) ->
  case openagentic_case_store_common_lookup:get_in_map(Package, [state, version_no], undefined) of
    Version when is_integer(Version), Version > 0 -> Version;
    _ -> 1
  end.

reconsideration_display_code(PackId, PackVersion) ->
  VersionBin = integer_to_binary(PackVersion),
  <<"PACK-", PackId/binary, "-V", VersionBin/binary>>.

start_reconsideration_gate(CaseDir, Package, Now) ->
  PackId = openagentic_case_store_common_lookup:get_in_map(Package, [links, pack_id], undefined),
  case load_pack(CaseDir, PackId) of
    {error, _} -> {error, reconsideration_package_not_actionable};
    {ok, Pack} ->
      PackSpec = pack_spec(Pack),
      FreshnessWindow = openagentic_case_store_common_lookup:choose_map(PackSpec, [freshness_window], #{max_age_seconds => 86400}),
      TaskBindings = openagentic_case_store_common_lookup:get_in_map(PackSpec, [task_bindings], []),
      CompletenessRule = openagentic_case_store_common_lookup:choose_map(PackSpec, [completeness_rule], #{mode => <<"all_required_reports_present">>}),
      Eval = evaluate_pack(CaseDir, TaskBindings, FreshnessWindow, Now),
      Completeness = openagentic_case_store_reconsideration_rules:evaluate_completeness_rule(Eval, CompletenessRule, Now),
      LatestLivePackageId =
        case latest_live_package(CaseDir, PackId) of
          undefined -> undefined;
          LivePackage -> object_id(LivePackage)
        end,
      openagentic_case_store_reconsideration_rules:can_start_deferred_package(Package, Completeness, LatestLivePackageId, Now)
  end.

pack_spec(Pack) ->
  openagentic_case_store_common_lookup:choose_map(Pack, [spec], #{}).

require_revision(Obj, Input0) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  case openagentic_case_store_common_lookup:get_int(Input, [current_revision, currentRevision], undefined) of
    undefined -> ok;
    ExpectedRevision ->
      Header = openagentic_case_store_common_lookup:get_in_map(Obj, [header], #{}),
      CurrentRevision = openagentic_case_store_common_lookup:get_int(Header, [revision], 0),
      case CurrentRevision =:= ExpectedRevision of
        true -> ok;
        false -> {error, {revision_conflict, CurrentRevision}}
      end
  end.

reconsideration_session_context(Package) ->
  #{
    package_id => object_id(Package),
    package_display_code => openagentic_case_store_common_lookup:get_in_map(Package, [state, display_code], undefined),
    package_version_no => openagentic_case_store_common_lookup:get_in_map(Package, [state, version_no], undefined),
    package_status => openagentic_case_store_common_lookup:get_in_map(Package, [state, status], undefined),
    frozen_payload => maps:get(frozen_payload, maps:get(ext, Package, #{}), #{})
  }.

based_on_round_snapshot(RootDir, CaseDir, CaseObj) ->
  case openagentic_case_store_common_lookup:get_in_map(CaseObj, [links, current_round_id], undefined) of
    undefined -> #{};
    RoundId ->
      case load_object(openagentic_case_store_repo_paths:round_file(CaseDir, RoundId)) of
        {error, _} -> #{id => RoundId};
        {ok, Round} ->
          WorkflowSessionId = openagentic_case_store_common_lookup:get_in_map(Round, [links, workflow_session_id], undefined),
          #{
            id => RoundId,
            workflow_session_id => WorkflowSessionId,
            kind => openagentic_case_store_common_lookup:get_in_map(Round, [spec, kind], undefined),
            status => openagentic_case_store_common_lookup:get_in_map(Round, [state, status], undefined),
            summary => round_summary_text(RootDir, WorkflowSessionId)
          }
      end
  end.

round_summary_text(_RootDir, undefined) -> <<>>;
round_summary_text(RootDir, WorkflowSessionId) ->
  Events = openagentic_session_store:read_events(RootDir, openagentic_case_store_common_core:ensure_list(WorkflowSessionId)),
  Event = openagentic_case_store_case_support:latest_workflow_done_event(Events),
  openagentic_case_store_common_lookup:get_bin(Event, [final_text], <<>>).

build_baseline_facts(CaseObj, BasedOnRound) ->
  lists:filtermap(
    fun
      ({case_summary, Summary}) when is_binary(Summary), Summary =/= <<>> ->
        {true, #{id => openagentic_case_store_common_meta:new_id(<<"baseline">>), category => <<"case_summary">>, summary => Summary}};
      ({prior_round_summary, Summary}) when is_binary(Summary), Summary =/= <<>> ->
        {true, #{id => openagentic_case_store_common_meta:new_id(<<"baseline">>), category => <<"prior_round_summary">>, summary => Summary}};
      (_) -> false
    end,
    [
      {case_summary, openagentic_case_store_common_lookup:get_in_map(CaseObj, [state, current_summary], <<>>)},
      {prior_round_summary, maps:get(summary, BasedOnRound, <<>>)}
    ]
  ).

build_change_facts(Reports) ->
  [
    #{
      id => openagentic_case_store_common_meta:new_id(<<"change">>),
      report_id => object_id(Report),
      task_id => openagentic_case_store_common_lookup:get_in_map(Report, [links, task_id], undefined),
      run_id => openagentic_case_store_common_lookup:get_in_map(Report, [links, run_id], undefined),
      category => report_change_category(Report),
      summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], <<"monitoring report submitted">>)
    }
   || Report <- Reports
  ].

report_change_category(Report) ->
  case openagentic_case_store_common_lookup:get_in_map(Report, [state, alert_summary], undefined) of
    Alert when is_binary(Alert), Alert =/= <<>> -> <<"risk_escalation">>;
    _ -> <<"confirmed_signal">>
  end.

maybe_supersede_live_package(_CaseDir, undefined, _PackageId, _Now) -> ok;
maybe_supersede_live_package(CaseDir, Package0, PackageId, Now) ->
  PrevId = object_id(Package0),
  Package1 = openagentic_case_store_repo_persist:update_object(Package0, Now, fun (Obj) -> Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"superseded">>}), ext => maps:merge(maps:get(ext, Obj, #{}), #{superseded_by_package_id => PackageId})} end),
  openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PrevId), Package1).

frozen_payload(RootDir, CaseDir, CaseObj, Pack, Review, Reports) ->
  BasedOnRound = based_on_round_snapshot(RootDir, CaseDir, CaseObj),
  ReportItems = [#{report_id => object_id(Report), task_id => openagentic_case_store_common_lookup:get_in_map(Report, [links, task_id], undefined), run_id => openagentic_case_store_common_lookup:get_in_map(Report, [links, run_id], undefined), result_summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], <<"monitoring report submitted">>), delta_summary => openagentic_case_store_common_lookup:get_in_map(Report, [state, quality_summary], <<"monitoring report submitted">>)} || Report <- Reports],
  ChangeFacts = build_change_facts(Reports),
  UrgentRefs = openagentic_case_store_run_urgent_brief:included_urgent_refs(Reports),
  #{'case' => #{id => object_id(CaseObj), title => openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, title], <<"Case">>), display_code => openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, display_code], undefined)}, based_on_round => BasedOnRound, baseline_facts => build_baseline_facts(CaseObj, BasedOnRound), change_facts => ChangeFacts, urgent_refs => UrgentRefs, observation_pack => #{id => object_id(Pack), title => openagentic_case_store_common_lookup:get_in_map(Pack, [spec, title], <<"Observation Pack">>), target_question => openagentic_case_store_common_lookup:get_in_map(Pack, [spec, target_question], <<>>) }, inspection_review => #{id => object_id(Review), status => openagentic_case_store_common_lookup:get_in_map(Review, [state, status], <<>>), decision => openagentic_case_store_common_lookup:get_in_map(Review, [state, decision], <<>>), process_state => openagentic_case_store_common_lookup:get_in_map(Review, [state, process_state], undefined), status_history => openagentic_case_store_common_lookup:get_in_map(Review, [ext, status_history], []) }, reports => ReportItems, summary => #{trigger_reason => <<"inspection_completed">>, controversies => openagentic_case_store_common_lookup:get_in_map(Review, [spec, controversy_candidates], []), included_report_count => length(ReportItems), included_urgent_count => length(UrgentRefs), change_fact_count => length(ChangeFacts)}}.

ready_mail(CaseId, CaseObj, Pack, Review, Package, FrozenPayload, SourceOpId, Now) ->
  MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
  #{header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now), links => #{case_id => CaseId, related_object_refs => [#{type => <<"observation_pack">>, id => object_id(Pack)}, #{type => <<"inspection_review">>, id => object_id(Review)}, #{type => <<"reconsideration_package">>, id => object_id(Package)}], source_op_id => SourceOpId, source_session_id => undefined}, spec => #{message_type => <<"reconsideration_ready">>, title => <<"reconsideration package ready">>, summary => openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, title], <<"Case">>), recommended_action => <<"preview_reconsideration">>, available_actions => [<<"preview_reconsideration">>, <<"start_reconsideration">>, <<"continue_observing">>]}, state => #{status => <<"unread">>, severity => <<"normal">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined}, audit => #{issuer_role => <<"inspector">>}, ext => #{preview_url => preview_url(CaseId, object_id(Package)), snapshot => maps:get(summary, FrozenPayload, #{})}}.

preview_url(CaseId, PackageId) -> <<"/view/reconsideration-preview.html?case_id=", CaseId/binary, "&package_id=", PackageId/binary>>.

maybe_mark_pack_deferred(CaseDir, Package, Now) ->
  PackId = openagentic_case_store_common_lookup:get_in_map(Package, [links, pack_id], undefined),
  case load_pack(CaseDir, PackId) of
    {error, _} -> ok;
    {ok, Pack0} ->
      Pack1 = openagentic_case_store_repo_persist:update_object(Pack0, Now, fun (Obj) -> Obj#{links => maps:merge(maps:get(links, Obj, #{}), #{latest_briefing_id => object_id(Package)}), state => maps:merge(maps:get(state, Obj, #{}), #{latest_deferred_briefing_id => object_id(Package)})} end),
      openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:observation_pack_file(CaseDir, PackId), Pack1)
  end.

next_round_index(CaseDir) -> length(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))) + 1.

object_id(undefined) -> undefined;
object_id(Obj) -> openagentic_case_store_common_meta:id_of(Obj).

run_id(undefined) -> undefined;
run_id(Obj) -> openagentic_case_store_common_lookup:get_in_map(Obj, [links, run_id], undefined).

append_if_defined(undefined, List) -> List;
append_if_defined(Value, List) -> List ++ [Value].
