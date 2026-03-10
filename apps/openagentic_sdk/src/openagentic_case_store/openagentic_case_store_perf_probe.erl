-module(openagentic_case_store_perf_probe).
-export([run_baseline/0, run_baseline/1]).

-define(DEFAULT_CASE_COUNT, 100).
-define(DEFAULT_TASKS_PER_CASE, 5).
-define(DEFAULT_MAIL_PER_CASE, 10).
-define(DEFAULT_UNREAD_PER_CASE, 5).

run_baseline() ->
  run_baseline(#{}).

run_baseline(Opts0) ->
  Opts = openagentic_case_store_common_core:ensure_map(Opts0),
  Root = ensure_root(maps:get(output_root, Opts, undefined)),
  CaseCount = int_opt(Opts, case_count, ?DEFAULT_CASE_COUNT),
  TasksPerCase = int_opt(Opts, tasks_per_case, ?DEFAULT_TASKS_PER_CASE),
  ActiveTasksPerCase = erlang:min(TasksPerCase, int_opt(Opts, active_tasks_per_case, TasksPerCase)),
  ScheduledTasksPerCase = erlang:min(ActiveTasksPerCase, nonneg_int_opt(Opts, scheduled_tasks_per_case, 0)),
  RuntimeOpts = openagentic_case_store_common_core:ensure_map(maps:get(runtime_opts, Opts, #{})),
  MailPerCase = int_opt(Opts, mail_per_case, ?DEFAULT_MAIL_PER_CASE),
  UnreadPerCase = erlang:min(MailPerCase, int_opt(Opts, unread_per_case, ?DEFAULT_UNREAD_PER_CASE)),
  _ = filelib:ensure_dir(filename:join([Root, "x"])),
  StartedAt = openagentic_case_store_common_meta:now_ts(),
  CaseIds = prepare_dataset(Root, CaseCount, TasksPerCase, ActiveTasksPerCase, ScheduledTasksPerCase, MailPerCase, UnreadPerCase),
  TargetCaseId = case CaseIds of [] -> <<>>; _ -> lists:last(CaseIds) end,
  {OverviewUs, {ok, Overview}} = timer:tc(fun () -> openagentic_case_store:get_case_overview(Root, TargetCaseId) end),
  {InboxUs, {ok, InboxUnread}} = timer:tc(fun () -> openagentic_case_store:list_inbox(Root, #{status => <<"unread">>}) end),
  {SchedulerUs, {ok, SchedulerRes}} = timer:tc(fun () -> openagentic_case_scheduler_due_scan:scan_once(#{session_root => Root, runtime_opts => RuntimeOpts}) end),
  FinishedAt = openagentic_case_store_common_meta:now_ts(),
  #{
    dataset => #{
      root => openagentic_case_store_common_core:to_bin(Root),
      case_count => CaseCount,
      tasks_per_case => TasksPerCase,
      task_count => CaseCount * TasksPerCase,
      active_tasks_per_case => ActiveTasksPerCase,
      active_task_count => CaseCount * ActiveTasksPerCase,
      scheduled_tasks_per_case => ScheduledTasksPerCase,
      scheduled_task_count => CaseCount * ScheduledTasksPerCase,
      mail_per_case => MailPerCase,
      unread_per_case => UnreadPerCase,
      mail_count => CaseCount * MailPerCase,
      target_case_id => TargetCaseId
    },
    timings_ms => #{
      overview => us_to_ms(OverviewUs),
      inbox_unread => us_to_ms(InboxUs),
      scheduler_scan_once => us_to_ms(SchedulerUs)
    },
    observed => #{
      overview_task_count => length(maps:get(tasks, Overview, [])),
      overview_mail_count => length(maps:get(mail, Overview, [])),
      inbox_unread_count => length(InboxUnread),
      scheduler_triggered_run_count => maps:get(triggered_run_count, SchedulerRes, 0),
      scheduler_skipped_count => length(maps:get(skipped, SchedulerRes, []))
    },
    started_at => StartedAt,
    finished_at => FinishedAt
  }.

prepare_dataset(Root, CaseCount, TasksPerCase, ActiveTasksPerCase, ScheduledTasksPerCase, MailPerCase, UnreadPerCase) ->
  [create_case_dataset(Root, CaseIdx, TasksPerCase, ActiveTasksPerCase, ScheduledTasksPerCase, MailPerCase, UnreadPerCase) || CaseIdx <- lists:seq(1, CaseCount)].

create_case_dataset(Root, CaseIdx, TasksPerCase, ActiveTasksPerCase, ScheduledTasksPerCase, MailPerCase, UnreadPerCase) ->
  BaseNow = openagentic_case_store_common_meta:now_ts() + (CaseIdx / 1000),
  CaseId = binary_id([<<"perf_case_">>, integer_to_binary(CaseIdx)]),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  ok = openagentic_case_store_repo_paths:ensure_case_layout(CaseDir),
  CaseObj =
    #{
      header => openagentic_case_store_common_meta:header(CaseId, <<"governance_case">>, BaseNow),
      links => #{active_pack_ids => []},
      spec =>
        #{
          title => binary_id([<<"Perf Case ">>, integer_to_binary(CaseIdx)]),
          display_code => binary_id([<<"PERF-">>, integer_to_binary(CaseIdx)]),
          opening_brief => <<"performance baseline dataset">>,
          current_summary => <<"synthetic case for perf probe">>,
          default_timezone => <<"Asia/Shanghai">>
        },
      state => #{phase => <<"monitoring_active">>, active_task_count => ActiveTasksPerCase, active_pack_count => 0}
    },
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:case_file(CaseDir), CaseObj),
  lists:foreach(fun (TaskIdx) -> write_task_dataset(CaseDir, CaseId, CaseIdx, TaskIdx, ActiveTasksPerCase, ScheduledTasksPerCase, BaseNow + (TaskIdx / 10000)) end, lists:seq(1, TasksPerCase)),
  lists:foreach(fun (MailIdx) -> write_mail_dataset(CaseDir, CaseId, CaseIdx, MailIdx, UnreadPerCase, BaseNow + (MailIdx / 10000)) end, lists:seq(1, MailPerCase)),
  ok = openagentic_case_store_case_state:rebuild_indexes(Root, CaseId),
  CaseId.

write_task_dataset(CaseDir, CaseId, CaseIdx, TaskIdx, ActiveTasksPerCase, ScheduledTasksPerCase, Now) ->
  TaskId = binary_id([<<"perf_task_">>, integer_to_binary(CaseIdx), <<"_">>, integer_to_binary(TaskIdx)]),
  VersionId = binary_id([<<"perf_version_">>, integer_to_binary(CaseIdx), <<"_">>, integer_to_binary(TaskIdx)]),
  TaskStatus = case TaskIdx =< ActiveTasksPerCase of true -> <<"active">>; false -> <<"ready_to_activate">> end,
  IsScheduled = TaskIdx =< ScheduledTasksPerCase andalso TaskStatus =:= <<"active">>,
  Task =
    #{
      header => openagentic_case_store_common_meta:header(TaskId, <<"monitoring_task">>, Now),
      links => #{case_id => CaseId, active_version_id => VersionId},
      spec => #{title => binary_id([<<"Task ">>, integer_to_binary(CaseIdx), <<"-">>, integer_to_binary(TaskIdx)]), objective => <<"perf scheduler scan">>},
      state => #{status => TaskStatus, activated_at => Now}
    },
  Version =
    #{
      header => openagentic_case_store_common_meta:header(VersionId, <<"task_version">>, Now),
      links => #{task_id => TaskId, case_id => CaseId},
      spec =>
        #{
          schedule_policy =>
            case IsScheduled of
              true -> #{mode => <<"interval">>, timezone => <<"Asia/Shanghai">>, interval => #{value => 1, unit => <<"hours">>}};
              false -> #{mode => <<"manual">>, timezone => <<"Asia/Shanghai">>}
            end,
          report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}
        }
    },
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), Task),
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, VersionId), Version).

write_mail_dataset(CaseDir, CaseId, CaseIdx, MailIdx, UnreadPerCase, Now) ->
  MailId = binary_id([<<"perf_mail_">>, integer_to_binary(CaseIdx), <<"_">>, integer_to_binary(MailIdx)]),
  Status = case MailIdx =< UnreadPerCase of true -> <<"unread">>; false -> <<"read">> end,
  Mail =
    #{
      header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now),
      links => #{case_id => CaseId, related_object_refs => []},
      spec => #{title => binary_id([<<"Mail ">>, integer_to_binary(CaseIdx), <<"-">>, integer_to_binary(MailIdx)]), summary => <<"synthetic perf mail">>, message_type => <<"perf_notice">>, available_actions => []},
      state => #{status => Status, severity => <<"normal">>},
      audit => #{}
    },
  ok = openagentic_case_store_repo_persist:write_json(openagentic_case_store_repo_paths:mail_file(CaseDir, MailId), Mail).

ensure_root(undefined) ->
  {ok, Cwd} = file:get_cwd(),
  Root = filename:join([Cwd, ".tmp", "perf", integer_to_list(erlang:system_time(microsecond)) ++ "_" ++ integer_to_list(erlang:unique_integer([positive, monotonic]))]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root;
ensure_root(Value) ->
  Root = openagentic_case_store_common_core:ensure_list(Value),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

int_opt(Opts, Key, Default) ->
  case maps:get(Key, Opts, Default) of
    V when is_integer(V), V > 0 -> V;
    V when is_binary(V) ->
      case catch binary_to_integer(string:trim(V)) of
        I when is_integer(I), I > 0 -> I;
        _ -> Default
      end;
    V when is_list(V) ->
      case catch list_to_integer(string:trim(V)) of
        I when is_integer(I), I > 0 -> I;
        _ -> Default
      end;
    _ -> Default
  end.

nonneg_int_opt(Opts, Key, Default) ->
  case maps:get(Key, Opts, Default) of
    V when is_integer(V), V >= 0 -> V;
    V when is_binary(V) ->
      case catch binary_to_integer(string:trim(V)) of
        I when is_integer(I), I >= 0 -> I;
        _ -> Default
      end;
    V when is_list(V) ->
      case catch list_to_integer(string:trim(V)) of
        I when is_integer(I), I >= 0 -> I;
        _ -> Default
      end;
    _ -> Default
  end.

binary_id(Parts) -> iolist_to_binary(Parts).

us_to_ms(Us) when is_integer(Us) -> Us / 1000.0.
