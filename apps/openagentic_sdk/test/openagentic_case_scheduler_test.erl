-module(openagentic_case_scheduler_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [
  create_active_task_fixture/1,
  create_active_task_fixture/2,
  tmp_root/0
]).

-define(SCHEDULER_CANDIDATES_INDEX, "scheduler-candidates.json").

scheduler_tick_does_not_block_configure_call_test_() ->
  {timeout, 30, fun scheduler_tick_does_not_block_configure_call_body/0}.

scheduler_tick_does_not_block_configure_call_body() ->
  openagentic_web_runtime_test_support:reset_web_runtime(),
  Root = tmp_root(),
  {_CaseId, _TaskId} =
    create_active_task_fixture(
      Root,
      #{
        schedule_policy => #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 1, unit => <<"hours">>}},
        report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}
      }
    ),
  {ok, _} = openagentic_web_runtime_sup:ensure_started(),
  ok = openagentic_case_scheduler:configure(#{session_root => Root, runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_slow}}),
  SchedulerPid = whereis(openagentic_case_scheduler),
  ?assert(is_pid(SchedulerPid)),
  SchedulerPid ! tick,
  timer:sleep(100),
  Parent = self(),
  _Caller =
    spawn(
      fun () ->
        Started = erlang:monotonic_time(millisecond),
        Res = openagentic_case_scheduler:configure(#{session_root => Root, runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_slow}}),
        Parent ! {configure_done, erlang:monotonic_time(millisecond) - Started, Res}
      end
    ),
  receive
    {configure_done, ElapsedMs, ok} ->
      ?assert(ElapsedMs < 250)
  after 2000 ->
    ?assert(false)
  end,
  openagentic_web_runtime_test_support:reset_web_runtime(),
  ok.

scheduler_scan_uses_active_task_index_before_full_task_scan_test() ->
  Root = tmp_root(),
  {CaseId, _TaskId} = create_active_task_fixture(Root),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  PoisonTaskDir = filename:join([CaseDir, "meta", "tasks", "poison_task"]),
  ok = filelib:ensure_dir(filename:join([PoisonTaskDir, "x"])),
  ok = file:write_file(filename:join([PoisonTaskDir, "task.json"]), <<"{">>),
  {ok, Result} = openagentic_case_scheduler:run_once(#{session_root => Root, runtime_opts => #{}}),
  ?assertEqual(0, maps:get(triggered_run_count, Result)),
  ok.


scheduler_scan_prefers_scheduler_candidate_index_over_active_index_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} =
    create_active_task_fixture(
      Root,
      #{
        schedule_policy => #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 1, unit => <<"hours">>}}
      }
    ),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
  Task0 = openagentic_case_store_repo_persist:read_json(TaskPath),
  TaskState0 = maps:get(state, Task0, #{}),
  Task1 = Task0#{state => TaskState0#{activated_at => 32503680000}},
  ok = openagentic_case_store_repo_persist:write_json(TaskPath, Task1),
  IndexDir = filename:join([CaseDir, "meta", "indexes"]),
  PoisonTaskId = <<"poison_task">>,
  PoisonTaskDir = filename:join([CaseDir, "meta", "tasks", "poison_task"]),
  ok = filelib:ensure_dir(filename:join([PoisonTaskDir, "x"])),
  ok = file:write_file(filename:join([PoisonTaskDir, "task.json"]), <<"{">>),
  ok = openagentic_case_store_repo_persist:write_json(
    filename:join([IndexDir, "tasks-by-status.json"]),
    #{<<"active">> => [TaskId, PoisonTaskId]}
  ),
  ok = openagentic_case_store_repo_persist:write_json(
    filename:join([IndexDir, ?SCHEDULER_CANDIDATES_INDEX]),
    #{task_ids => [TaskId]}
  ),
  {ok, Result} = openagentic_case_scheduler:run_once(#{session_root => Root, runtime_opts => #{}}),
  ?assertEqual(0, maps:get(triggered_run_count, Result)),
  ok.

scheduler_rebuild_indexes_writes_only_scheduled_active_task_candidates_test() ->
  Root = tmp_root(),
  {CaseId, ScheduledTaskId} =
    create_active_task_fixture(
      Root,
      #{
        schedule_policy => #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 1, unit => <<"hours">>}}
      }
    ),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  ManualTaskId = <<"manual_task">>,
  ManualVersionId = <<"manual_version">>,
  ManualTask =
    #{
      header => openagentic_case_store_common_meta:header(ManualTaskId, <<"monitoring_task">>, 2000),
      links => #{case_id => CaseId, active_version_id => ManualVersionId},
      spec => #{title => <<"Manual Task">>, objective => <<"should not be scanned">>},
      state => #{status => <<"active">>, activated_at => 2000}
    },
  ManualVersion =
    #{
      header => openagentic_case_store_common_meta:header(ManualVersionId, <<"task_version">>, 2000),
      links => #{task_id => ManualTaskId, case_id => CaseId},
      spec => #{schedule_policy => #{mode => <<"manual">>, timezone => <<"Asia/Shanghai">>}}
    },
  ReadyTaskId = <<"ready_task">>,
  ReadyVersionId = <<"ready_version">>,
  ReadyTask =
    #{
      header => openagentic_case_store_common_meta:header(ReadyTaskId, <<"monitoring_task">>, 3000),
      links => #{case_id => CaseId, active_version_id => ReadyVersionId},
      spec => #{title => <<"Ready Task">>, objective => <<"inactive scheduled task">>},
      state => #{status => <<"ready_to_activate">>, activated_at => 3000}
    },
  ReadyVersion =
    #{
      header => openagentic_case_store_common_meta:header(ReadyVersionId, <<"task_version">>, 3000),
      links => #{task_id => ReadyTaskId, case_id => CaseId},
      spec => #{schedule_policy => #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 2, unit => <<"hours">>}}}
    },
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_file(CaseDir, ManualTaskId), ManualTask),
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_version_file(CaseDir, ManualTaskId, ManualVersionId), ManualVersion),
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_file(CaseDir, ReadyTaskId), ReadyTask),
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_version_file(CaseDir, ReadyTaskId, ReadyVersionId), ReadyVersion),
  ok = openagentic_case_store_case_state:rebuild_indexes(Root, CaseId),
  SchedulerCandidatesPath = filename:join([CaseDir, "meta", "indexes", ?SCHEDULER_CANDIDATES_INDEX]),
  SchedulerCandidates = openagentic_case_store_repo_persist:read_json(SchedulerCandidatesPath),
  ?assertEqual([ScheduledTaskId], maps:get(task_ids, SchedulerCandidates, [])),
  ok.
