-module(openagentic_case_store_case_state).
-export([get_case_overview_map/2, refresh_case_state/2, counts_as_live_task/1, rebuild_indexes/2, group_ids_by_status/1]).

get_case_overview_map(RootDir, CaseId) ->
  {ok, CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Rounds = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  Candidates = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"]))),
  Tasks = openagentic_case_store_repo_readers:read_task_objects_indexed(CaseDir),
  Mail = openagentic_case_store_repo_readers:read_mail_objects_indexed(CaseDir, undefined),
  Templates = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_template_objects(filename:join([CaseDir, "meta", "templates"]))),
  Packs = openagentic_case_store_repo_readers:read_observation_packs_indexed(CaseDir),
  Reviews = openagentic_case_store_repo_readers:read_inspection_reviews_indexed(CaseDir),
  Packages = openagentic_case_store_repo_readers:read_reconsideration_packages_indexed(CaseDir),
  #{'case' => CaseObj, rounds => Rounds, candidates => Candidates, tasks => Tasks, templates => Templates, mail => Mail, observation_packs => Packs, inspection_reviews => Reviews, reconsideration_packages => Packages}.

refresh_case_state(RootDir, CaseId) ->
  {ok, CaseObj0, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Tasks = openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  Packs = openagentic_case_store_repo_readers:read_observation_packs(CaseDir),
  Packages = openagentic_case_store_repo_readers:read_reconsideration_packages(CaseDir),
  ActiveTaskCount =
    length(
      [
        T
       || T <- Tasks,
          counts_as_live_task(openagentic_case_store_common_lookup:get_in_map(T, [state, status], <<>>))
      ]
    ),
  ActivePackIds =
    [
      openagentic_case_store_common_meta:id_of(Pack)
     || Pack <- Packs,
        lists:member(openagentic_case_store_common_lookup:get_in_map(Pack, [state, status], <<>>), [<<"collecting">>, <<"awaiting_inspection">>, <<"ready_for_reconsideration">>, <<"insufficient">>, <<"stale">>])
    ],
  ActivePackCount = length(ActivePackIds),
  Phase = derive_case_phase(ActiveTaskCount, Packages),
  CaseObj1 =
    openagentic_case_store_repo_persist:update_object(
      CaseObj0,
      openagentic_case_store_common_meta:now_ts(),
      fun (Obj) ->
        Links0 = maps:get(links, Obj, #{}),
        State0 = maps:get(state, Obj, #{}),
        Obj#{links => Links0#{active_pack_ids => ActivePackIds}, state => State0#{active_task_count => ActiveTaskCount, active_pack_count => ActivePackCount, phase => Phase}}
      end
    ),
  openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:case_file(CaseDir), CaseObj1).

counts_as_live_task(<<"active">>) -> true;
counts_as_live_task(<<"rectification_required">>) -> true;
counts_as_live_task(_) -> false.

rebuild_indexes(RootDir, CaseId) ->
  {ok, _CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Candidates = openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"])),
  Tasks = openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  Mail = openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "mail"])),
  Packs = openagentic_case_store_repo_readers:read_observation_packs(CaseDir),
  Reviews = openagentic_case_store_repo_readers:read_inspection_reviews(CaseDir),
  Packages = openagentic_case_store_repo_readers:read_reconsideration_packages(CaseDir),
  IndexDir = filename:join([CaseDir, "meta", "indexes"]),
  SchedulerCandidateTaskIds = scheduler_candidate_task_ids(CaseDir, Tasks),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "candidates-by-status.json"]), group_ids_by_status(Candidates)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "tasks-by-status.json"]), group_ids_by_status(Tasks)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "scheduler-candidates.json"]), #{task_ids => SchedulerCandidateTaskIds}),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "packs-by-status.json"]), group_ids_by_status(Packs)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "inspection-reviews-by-status.json"]), group_ids_by_status(Reviews)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "reconsideration-packages-by-status.json"]), group_ids_by_status(Packages)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "mail-by-status.json"]), group_ids_by_status(Mail)),
  UnreadMail = [openagentic_case_store_common_meta:id_of(M) || M <- Mail, openagentic_case_store_common_lookup:get_in_map(M, [state, status], <<>>) =:= <<"unread">>],
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "mail-unread.json"]), #{mail_ids => UnreadMail}),
  ok.

scheduler_candidate_task_ids(CaseDir, Tasks0) ->
  Tasks = [openagentic_case_store_common_core:ensure_map(Task) || Task <- Tasks0],
  openagentic_case_store_common_core:unique_binaries(
    [
      TaskId
     || Task <- Tasks,
        openagentic_case_store_common_lookup:get_in_map(Task, [state, status], <<>>) =:= <<"active">>,
        TaskId <- [openagentic_case_store_common_meta:id_of(Task)],
        TaskId =/= undefined,
        task_has_scheduler_candidate_policy(CaseDir, TaskId, Task)
    ]
  ).

task_has_scheduler_candidate_policy(CaseDir, TaskId, Task) ->
  Version = load_active_task_version(CaseDir, TaskId, Task),
  schedule_policy_is_scheduler_candidate(openagentic_case_store_common_lookup:get_in_map(Version, [spec, schedule_policy], #{})).

load_active_task_version(CaseDir, TaskId, Task) ->
  ActiveVersionId = openagentic_case_store_common_lookup:get_in_map(Task, [links, active_version_id], undefined),
  case load_task_version_file(CaseDir, TaskId, ActiveVersionId) of
    undefined ->
      case openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId) of
        [] -> #{};
        Versions -> lists:last(Versions)
      end;
    Version -> Version
  end.

load_task_version_file(_CaseDir, _TaskId, undefined) -> undefined;
load_task_version_file(CaseDir, TaskId, VersionId) ->
  Path = openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, VersionId),
  case filelib:is_file(Path) of
    true -> openagentic_case_store_repo_persist:read_json(Path);
    false -> undefined
  end.

schedule_policy_is_scheduler_candidate(Policy0) ->
  Policy = openagentic_case_store_common_core:ensure_map(Policy0),
  Mode = openagentic_case_store_common_core:to_bin(openagentic_case_store_common_lookup:get_in_map(Policy, [mode], <<"manual">>)),
  IntervalSeconds = openagentic_case_scheduler_time:interval_seconds(openagentic_case_store_common_lookup:get_in_map(Policy, [interval], #{})),
  FixedTimes = openagentic_case_scheduler_time:parse_fixed_times(openagentic_case_store_common_lookup:get_in_map(Policy, [fixed_times], [])),
  case Mode of
    <<"manual">> -> false;
    <<"interval">> -> is_integer(IntervalSeconds) andalso IntervalSeconds > 0;
    <<"fixed_times">> -> FixedTimes =/= [];
    <<"fixed_time">> -> FixedTimes =/= [];
    _ -> (FixedTimes =/= []) orelse (is_integer(IntervalSeconds) andalso IntervalSeconds > 0)
  end.

derive_case_phase(ActiveTaskCount, Packages) ->
  case latest_effective_package_status(Packages) of
    <<"consumed_by_round">> -> <<"reconsideration_in_progress">>;
    <<"ready">> -> <<"briefing_ready">>;
    <<"deferred">> -> <<"briefing_deferred">>;
    _ -> derive_monitoring_phase(ActiveTaskCount)
  end.

derive_monitoring_phase(ActiveTaskCount) when ActiveTaskCount > 0 -> <<"monitoring_active">>;
derive_monitoring_phase(_) -> <<"post_deliberation_extraction">>.

latest_package_status([]) -> undefined;
latest_package_status(Packages) ->
  Latest = lists:last(openagentic_case_store_repo_readers:sort_by_created_at(Packages)),
  openagentic_case_store_common_lookup:get_in_map(Latest, [state, status], undefined).

latest_effective_package_status(Packages) ->
  case [Package || Package <- Packages, openagentic_case_store_common_lookup:get_in_map(Package, [state, status], <<>>) =/= <<"superseded">>] of
    [] -> latest_package_status(Packages);
    LivePackages -> latest_package_status(LivePackages)
  end.

group_ids_by_status(Objs) ->
  lists:foldl(
    fun (Obj, Acc0) ->
      Status = openagentic_case_store_common_lookup:get_in_map(Obj, [state, status], <<"unknown">>),
      Id = openagentic_case_store_common_meta:id_of(Obj),
      Prev = maps:get(Status, Acc0, []),
      Acc0#{Status => Prev ++ [Id]}
    end,
    #{},
    Objs
  ).
