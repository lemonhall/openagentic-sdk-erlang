-module(openagentic_case_scheduler_due_scan).
-export([scan_once/1]).

scan_once(Opts0) ->
  Opts = openagentic_case_scheduler_utils:ensure_map(Opts0),
  SessionRoot = openagentic_case_scheduler_utils:ensure_list(maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined))),
  RuntimeOpts = openagentic_case_scheduler_utils:ensure_map(maps:get(runtime_opts, Opts, maps:get(runtimeOpts, Opts, #{}))),
  case SessionRoot of
    [] -> {ok, #{triggered_run_count => 0, triggered => [], skipped => []}};
    _ ->
      CaseDirs = filelib:wildcard(filename:join([SessionRoot, "cases", "*"])),
      Now = openagentic_case_scheduler_time:now_ts(),
      {TriggeredCount, Triggered, Skipped} =
        lists:foldl(
          fun (CaseDir, Acc0) ->
            TaskPaths = task_paths(CaseDir),
            lists:foldl(fun (TaskPath, Acc1) -> openagentic_case_scheduler_dispatch:dispatch_task(SessionRoot, RuntimeOpts, Now, CaseDir, TaskPath, Acc1) end, Acc0, TaskPaths)
          end,
          {0, [], []},
          CaseDirs
        ),
      {ok, #{triggered_run_count => TriggeredCount, triggered => lists:reverse(Triggered), skipped => lists:reverse(Skipped)}}
  end.

task_paths(CaseDir) ->
  case indexed_scheduler_candidate_task_ids(CaseDir) of
    {ok, TaskIds} -> task_paths_for_ids(CaseDir, TaskIds);
    error ->
      case indexed_active_task_ids(CaseDir) of
        {ok, TaskIds} -> task_paths_for_ids(CaseDir, TaskIds);
        error -> filelib:wildcard(filename:join([CaseDir, "meta", "tasks", "*", "task.json"]))
      end
  end.

task_paths_for_ids(CaseDir, TaskIds) ->
  [
    Path
   || TaskId <- TaskIds,
      Path <- [filename:join([CaseDir, "meta", "tasks", openagentic_case_scheduler_utils:ensure_list(TaskId), "task.json"])],
      filelib:is_file(Path)
  ].

indexed_scheduler_candidate_task_ids(CaseDir) ->
  read_indexed_task_ids(filename:join([CaseDir, "meta", "indexes", "scheduler-candidates.json"]), [task_ids]).

indexed_active_task_ids(CaseDir) ->
  read_indexed_task_ids(filename:join([CaseDir, "meta", "indexes", "tasks-by-status.json"]), [active]).

read_indexed_task_ids(IndexPath, KeyPath) ->
  case filelib:is_file(IndexPath) of
    false -> error;
    true ->
      try
        Index = openagentic_case_scheduler_store:read_json(IndexPath),
        {ok, normalize_task_ids(openagentic_case_scheduler_utils:get_in_map(Index, KeyPath, []))}
      catch
        _:_ -> error
      end
  end.

normalize_task_ids(Ids0) when is_list(Ids0) ->
  lists:usort([Id || Id <- [openagentic_case_scheduler_utils:to_bin(Value) || Value <- Ids0], Id =/= <<>>]);
normalize_task_ids(undefined) -> [];
normalize_task_ids(null) -> [];
normalize_task_ids(Id) -> normalize_task_ids([Id]).
