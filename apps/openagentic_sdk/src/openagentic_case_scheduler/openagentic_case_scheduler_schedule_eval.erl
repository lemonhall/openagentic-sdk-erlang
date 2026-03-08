-module(openagentic_case_scheduler_schedule_eval).
-export([due_run_spec/3]).

due_run_spec(CaseDir, Task0, Now) ->
  Task = openagentic_case_scheduler_utils:ensure_map(Task0),
  TaskId = openagentic_case_scheduler_store:id_of(Task),
  case openagentic_case_scheduler_utils:get_in_map(Task, [state, status], <<>>) of
    <<"active">> ->
      Runs = openagentic_case_scheduler_store:read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", openagentic_case_scheduler_utils:ensure_list(TaskId), "runs"])),
      case latest_run_blocks_schedule(Runs) of
        true -> undefined;
        false ->
          Version = load_task_version(CaseDir, Task),
          SchedulePolicy = openagentic_case_scheduler_utils:ensure_map(openagentic_case_scheduler_utils:get_in_map(Version, [spec, schedule_policy], #{})),
          due_run_spec_for_policy(Task, Runs, SchedulePolicy, Now)
      end;
    _ -> undefined
  end.

load_task_version(CaseDir, Task0) ->
  Task = openagentic_case_scheduler_utils:ensure_map(Task0),
  TaskId = openagentic_case_scheduler_store:id_of(Task),
  ActiveVersionId = openagentic_case_scheduler_utils:get_in_map(Task, [links, active_version_id], undefined),
  Path = filename:join([CaseDir, "meta", "tasks", openagentic_case_scheduler_utils:ensure_list(TaskId), "versions", openagentic_case_scheduler_utils:ensure_list(ActiveVersionId) ++ ".json"]),
  case filelib:is_file(Path) of
    true -> openagentic_case_scheduler_store:read_json(Path);
    false ->
      Versions = openagentic_case_scheduler_store:read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", openagentic_case_scheduler_utils:ensure_list(TaskId), "versions"])),
      case openagentic_case_scheduler_store:sort_by_created_at(Versions) of [] -> #{}; Sorted -> lists:last(Sorted) end
  end.

latest_run_blocks_schedule([]) -> false;
latest_run_blocks_schedule(Runs0) ->
  Runs = openagentic_case_scheduler_store:sort_by_created_at([openagentic_case_scheduler_utils:ensure_map(R) || R <- Runs0]),
  case lists:reverse(Runs) of
    [Run | _] ->
      Status = openagentic_case_scheduler_utils:get_in_map(Run, [state, status], <<>>),
      Status =:= <<"running">> orelse Status =:= <<"scheduled">>;
    [] -> false
  end.

due_run_spec_for_policy(Task, Runs0, Policy0, Now) ->
  Policy = openagentic_case_scheduler_utils:ensure_map(Policy0),
  Mode = openagentic_case_scheduler_utils:get_bin(Policy, [mode], <<"manual">>),
  OffsetSeconds = openagentic_case_scheduler_time:timezone_offset_seconds(Policy),
  case openagentic_case_scheduler_time:within_active_windows(Now, OffsetSeconds, openagentic_case_scheduler_utils:get_in_map(Policy, [windows], [])) of
    false -> undefined;
    true ->
      case Mode of
        <<"manual">> -> undefined;
        <<"interval">> -> due_interval(Task, Runs0, Policy, Now);
        <<"fixed_times">> -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now);
        <<"fixed_time">> -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now);
        _ -> case openagentic_case_scheduler_utils:get_in_map(Policy, [fixed_times], []) of [] -> due_interval(Task, Runs0, Policy, Now); _ -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now) end
      end
  end.

due_interval(Task, Runs0, Policy, Now) ->
  Runs = [openagentic_case_scheduler_utils:ensure_map(R) || R <- Runs0],
  case openagentic_case_scheduler_time:interval_seconds(openagentic_case_scheduler_utils:get_in_map(Policy, [interval], #{})) of
    undefined -> undefined;
    Sec when Sec =< 0 -> undefined;
    Sec ->
      PlannedForAt = case latest_run_anchor(Runs) of undefined -> openagentic_case_scheduler_utils:get_in_map(Task, [state, activated_at], Now); Ts -> Ts + Sec end,
      case Now >= PlannedForAt of true -> #{planned_for_at => PlannedForAt, trigger_ref => <<"schedule_policy:interval">>}; false -> undefined end
  end.

due_fixed_times(Runs0, Policy, OffsetSeconds, Now) ->
  case openagentic_case_scheduler_time:parse_fixed_times(openagentic_case_scheduler_utils:get_in_map(Policy, [fixed_times], [])) of
    [] -> undefined;
    FixedTimes ->
      LocalNow = trunc(Now) + OffsetSeconds,
      {{_Y, _Mo, _D}, {H, Mi, S}} = openagentic_case_scheduler_time:unix_to_datetime(LocalNow),
      CurrentSecOfDay = H * 3600 + Mi * 60 + S,
      CandidateSecs = [Sec || Sec <- FixedTimes, Sec =< CurrentSecOfDay],
      case CandidateSecs of
        [] -> undefined;
        _ ->
          SlotSec = lists:last(lists:sort(CandidateSecs)),
          PlannedForAt = ((LocalNow - CurrentSecOfDay) - OffsetSeconds) + SlotSec,
          LastTs = latest_run_anchor([openagentic_case_scheduler_utils:ensure_map(R) || R <- Runs0]),
          case LastTs =:= undefined orelse LastTs < PlannedForAt of true -> #{planned_for_at => PlannedForAt, trigger_ref => <<"schedule_policy:fixed_times">>}; false -> undefined end
      end
  end.

latest_run_anchor([]) -> undefined;
latest_run_anchor(Runs0) ->
  Runs = openagentic_case_scheduler_store:sort_by_created_at([openagentic_case_scheduler_utils:ensure_map(R) || R <- Runs0]),
  case lists:reverse(Runs) of
    [Run | _] ->
      openagentic_case_scheduler_store:first_number([
        openagentic_case_scheduler_utils:get_in_map(Run, [state, completed_at], undefined),
        openagentic_case_scheduler_utils:get_in_map(Run, [state, started_at], undefined),
        openagentic_case_scheduler_utils:get_in_map(Run, [audit, triggered_at], undefined),
        openagentic_case_scheduler_utils:get_in_map(Run, [spec, planned_for_at], undefined)
      ]);
    [] -> undefined
  end.
