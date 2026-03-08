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
            TaskPaths = filelib:wildcard(filename:join([CaseDir, "meta", "tasks", "*", "task.json"])),
            lists:foldl(fun (TaskPath, Acc1) -> openagentic_case_scheduler_dispatch:dispatch_task(SessionRoot, RuntimeOpts, Now, CaseDir, TaskPath, Acc1) end, Acc0, TaskPaths)
          end,
          {0, [], []},
          CaseDirs
        ),
      {ok, #{triggered_run_count => TriggeredCount, triggered => lists:reverse(Triggered), skipped => lists:reverse(Skipped)}}
  end.
