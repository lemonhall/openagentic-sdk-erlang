-module(openagentic_case_scheduler_dispatch).
-export([dispatch_task/6]).

dispatch_task(SessionRoot, RuntimeOpts, Now, CaseDir, TaskPath, {Count1, Triggered1, Skipped1}) ->
  Task = openagentic_case_scheduler_store:read_json(TaskPath),
  CaseId = openagentic_case_scheduler_utils:get_in_map(Task, [links, case_id], undefined),
  TaskId = openagentic_case_scheduler_store:id_of(Task),
  case openagentic_case_scheduler_schedule_eval:due_run_spec(CaseDir, Task, Now) of
    undefined -> {Count1, Triggered1, Skipped1};
    DueSpec ->
      Payload = DueSpec#{case_id => CaseId, task_id => TaskId, run_kind => <<"scheduled">>, trigger_type => <<"schedule_policy">>, runtime_opts => RuntimeOpts},
      case openagentic_case_store:run_task(SessionRoot, Payload) of
        {ok, _Res} ->
          Triggered = openagentic_case_scheduler_utils:compact_map(#{case_id => CaseId, task_id => TaskId, planned_for_at => maps:get(planned_for_at, DueSpec, undefined)}),
          {Count1 + 1, [Triggered | Triggered1], Skipped1};
        {error, Reason} ->
          Skipped = openagentic_case_scheduler_utils:compact_map(#{case_id => CaseId, task_id => TaskId, reason => openagentic_case_scheduler_utils:to_bin(Reason)}),
          {Count1, Triggered1, [Skipped | Skipped1]};
        _ ->
          Skipped = openagentic_case_scheduler_utils:compact_map(#{case_id => CaseId, task_id => TaskId, reason => <<"unknown">>}),
          {Count1, Triggered1, [Skipped | Skipped1]}
      end
  end.
