-module(openagentic_case_scheduler).

-behaviour(gen_server).

-export([start_link/0, configure/1, run_once/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TICK_MS, 5000).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, #{}, []).

configure(Opts0) ->
  Opts = ensure_map(Opts0),
  gen_server:call(?SERVER, {configure, Opts}, 60000).

run_once(Opts0) ->
  scan_once(ensure_map(Opts0)).

init(_InitArg) ->
  _ = erlang:send_after(?DEFAULT_TICK_MS, self(), tick),
  {ok, #{enabled => false, session_root => undefined, runtime_opts => #{}, tick_ms => ?DEFAULT_TICK_MS}}.

handle_call({configure, Opts0}, _From, State0) ->
  Opts = ensure_map(Opts0),
  SessionRoot = ensure_list(maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined))),
  TickMs = int_or_default(maps:get(case_scheduler_tick_ms, Opts, maps:get(caseSchedulerTickMs, Opts, ?DEFAULT_TICK_MS)), ?DEFAULT_TICK_MS),
  RuntimeOpts =
    maps:without(
      [web_bind, web_port, bind, port, project_dir, session_root, sessionRoot, case_scheduler_tick_ms, caseSchedulerTickMs],
      Opts
    ),
  State1 =
    State0#{
      enabled => SessionRoot =/= [] andalso SessionRoot =/= "undefined",
      session_root => SessionRoot,
      runtime_opts => RuntimeOpts,
      tick_ms => TickMs
    },
  {reply, ok, State1};
handle_call(_Msg, _From, State) ->
  {reply, {error, unsupported}, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(tick, State0) ->
  TickMs = maps:get(tick_ms, State0, ?DEFAULT_TICK_MS),
  _ = erlang:send_after(TickMs, self(), tick),
  case maps:get(enabled, State0, false) of
    true ->
      _ =
        catch
          scan_once(
            #{session_root => maps:get(session_root, State0, undefined), runtime_opts => maps:get(runtime_opts, State0, #{})}
          ),
      {noreply, State0};
    false ->
      {noreply, State0}
  end;
handle_info(_Info, State) ->
  {noreply, State}.

scan_once(Opts0) ->
  Opts = ensure_map(Opts0),
  SessionRoot = ensure_list(maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined))),
  RuntimeOpts = ensure_map(maps:get(runtime_opts, Opts, maps:get(runtimeOpts, Opts, #{}))),
  case SessionRoot of
    [] -> {ok, #{triggered_run_count => 0, triggered => [], skipped => []}};
    _ ->
      CaseDirs = filelib:wildcard(filename:join([SessionRoot, "cases", "*"])),
      Now = now_ts(),
      {TriggeredCount, Triggered, Skipped} =
        lists:foldl(
          fun (CaseDir, {Count0, Triggered0, Skipped0}) ->
            TaskPaths = filelib:wildcard(filename:join([CaseDir, "meta", "tasks", "*", "task.json"])),
            lists:foldl(
              fun (TaskPath, {Count1, Triggered1, Skipped1}) ->
                Task = read_json(TaskPath),
                CaseId = get_in_map(Task, [links, case_id], undefined),
                TaskId = id_of(Task),
                case due_run_spec(CaseDir, Task, Now) of
                  undefined ->
                    {Count1, Triggered1, Skipped1};
                  DueSpec ->
                    Payload =
                      DueSpec#{
                        case_id => CaseId,
                        task_id => TaskId,
                        run_kind => <<"scheduled">>,
                        trigger_type => <<"schedule_policy">>,
                        runtime_opts => RuntimeOpts
                      },
                    case openagentic_case_store:run_task(SessionRoot, Payload) of
                      {ok, _Res} ->
                        {Count1 + 1, [compact_map(#{case_id => CaseId, task_id => TaskId, planned_for_at => maps:get(planned_for_at, DueSpec, undefined)}) | Triggered1], Skipped1};
                      {error, Reason} ->
                        {Count1, Triggered1, [compact_map(#{case_id => CaseId, task_id => TaskId, reason => to_bin(Reason)}) | Skipped1]};
                      _ ->
                        {Count1, Triggered1, [compact_map(#{case_id => CaseId, task_id => TaskId, reason => <<"unknown">>}) | Skipped1]}
                    end
                end
              end,
              {Count0, Triggered0, Skipped0},
              TaskPaths
            )
          end,
          {0, [], []},
          CaseDirs
        ),
      {ok, #{triggered_run_count => TriggeredCount, triggered => lists:reverse(Triggered), skipped => lists:reverse(Skipped)}}
  end.

due_run_spec(CaseDir, Task0, Now) ->
  Task = ensure_map(Task0),
  TaskId = id_of(Task),
  case get_in_map(Task, [state, status], <<>>) of
    <<"active">> ->
      Runs = read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", ensure_list(TaskId), "runs"])),
      case latest_run_blocks_schedule(Runs) of
        true -> undefined;
        false ->
          Version = load_task_version(CaseDir, Task),
          SchedulePolicy = ensure_map(get_in_map(Version, [spec, schedule_policy], #{})),
          due_run_spec_for_policy(Task, Runs, SchedulePolicy, Now)
      end;
    _ ->
      undefined
  end.

load_task_version(CaseDir, Task0) ->
  Task = ensure_map(Task0),
  TaskId = id_of(Task),
  ActiveVersionId = get_in_map(Task, [links, active_version_id], undefined),
  Path = filename:join([CaseDir, "meta", "tasks", ensure_list(TaskId), "versions", ensure_list(ActiveVersionId) ++ ".json"]),
  case filelib:is_file(Path) of
    true -> read_json(Path);
    false ->
      Versions = read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", ensure_list(TaskId), "versions"])),
      case sort_by_created_at(Versions) of
        [] -> #{};
        Sorted -> lists:last(Sorted)
      end
  end.

latest_run_blocks_schedule([]) -> false;
latest_run_blocks_schedule(Runs0) ->
  Runs = sort_by_created_at([ensure_map(R) || R <- Runs0]),
  case lists:reverse(Runs) of
    [Run | _] ->
      Status = get_in_map(Run, [state, status], <<>>),
      Status =:= <<"running">> orelse Status =:= <<"scheduled">>;
    [] ->
      false
  end.

due_run_spec_for_policy(Task, Runs0, Policy0, Now) ->
  Policy = ensure_map(Policy0),
  Mode = get_bin(Policy, [mode], <<"manual">>),
  OffsetSeconds = timezone_offset_seconds(Policy),
  case within_active_windows(Now, OffsetSeconds, get_in_map(Policy, [windows], [])) of
    false -> undefined;
    true ->
      case Mode of
        <<"manual">> -> undefined;
        <<"interval">> -> due_interval(Task, Runs0, Policy, Now);
        <<"fixed_times">> -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now);
        <<"fixed_time">> -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now);
        _ ->
          case get_in_map(Policy, [fixed_times], []) of
            [] -> due_interval(Task, Runs0, Policy, Now);
            _ -> due_fixed_times(Runs0, Policy, OffsetSeconds, Now)
          end
      end
  end.

due_interval(Task, Runs0, Policy, Now) ->
  Runs = [ensure_map(R) || R <- Runs0],
  IntervalSeconds = interval_seconds(get_in_map(Policy, [interval], #{})),
  case IntervalSeconds of
    undefined -> undefined;
    Sec when Sec =< 0 -> undefined;
    Sec ->
      LastTs = latest_run_anchor(Runs),
      PlannedForAt =
        case LastTs of
          undefined -> get_in_map(Task, [state, activated_at], Now);
          Ts -> Ts + Sec
        end,
      case Now >= PlannedForAt of
        true -> #{planned_for_at => PlannedForAt, trigger_ref => <<"schedule_policy:interval">>};
        false -> undefined
      end
  end.

due_fixed_times(Runs0, Policy, OffsetSeconds, Now) ->
  FixedTimes = parse_fixed_times(get_in_map(Policy, [fixed_times], [])),
  case FixedTimes of
    [] -> undefined;
    _ ->
      LocalNow = trunc(Now) + OffsetSeconds,
      {{_Y, _Mo, _D}, {H, Mi, S}} = unix_to_datetime(LocalNow),
      CurrentSecOfDay = H * 3600 + Mi * 60 + S,
      CandidateSecs = [Sec || Sec <- FixedTimes, Sec =< CurrentSecOfDay],
      case CandidateSecs of
        [] -> undefined;
        _ ->
          SlotSec = lists:last(lists:sort(CandidateSecs)),
          LocalDayStart = LocalNow - CurrentSecOfDay,
          PlannedForAt = (LocalDayStart - OffsetSeconds) + SlotSec,
          LastTs = latest_run_anchor([ensure_map(R) || R <- Runs0]),
          case LastTs =:= undefined orelse LastTs < PlannedForAt of
            true -> #{planned_for_at => PlannedForAt, trigger_ref => <<"schedule_policy:fixed_times">>};
            false -> undefined
          end
      end
  end.

parse_fixed_times([]) -> [];
parse_fixed_times([Item | Rest]) ->
  case fixed_time_seconds(Item) of
    undefined -> parse_fixed_times(Rest);
    Sec -> [Sec | parse_fixed_times(Rest)]
  end;
parse_fixed_times(Item) ->
  case fixed_time_seconds(Item) of
    undefined -> [];
    Sec -> [Sec]
  end.

fixed_time_seconds(Item0) ->
  Item = ensure_map(Item0),
  case Item of
    #{} when map_size(Item) > 0 ->
      Hour = int_or_default(find_any(Item, [hour]), 0),
      Minute = int_or_default(find_any(Item, [minute]), 0),
      clamp_range(Hour, 0, 23) * 3600 + clamp_range(Minute, 0, 59) * 60;
    _ ->
      Bin = string:trim(to_bin(Item0)),
      case binary:split(Bin, <<":">>, [global]) of
        [HBin, MBin] -> clamp_range(int_or_default(HBin, 0), 0, 23) * 3600 + clamp_range(int_or_default(MBin, 0), 0, 59) * 60;
        _ -> undefined
      end
  end.

within_active_windows(_Now, _OffsetSeconds, []) -> true;
within_active_windows(Now, OffsetSeconds, Windows0) when is_list(Windows0) ->
  LocalNow = trunc(Now) + OffsetSeconds,
  {{_Y, _Mo, _D}, {H, Mi, S}} = unix_to_datetime(LocalNow),
  DayOfWeek = calendar:day_of_the_week(date_of_ts(LocalNow)),
  SecOfDay = H * 3600 + Mi * 60 + S,
  lists:any(
    fun (Window0) ->
      Window = ensure_map(Window0),
      Days = normalize_weekdays(get_in_map(Window, [weekdays], get_in_map(Window, [days], []))),
      StartSec = fixed_time_seconds(find_any(Window, [start, start_time, startTime])),
      EndSec = fixed_time_seconds(find_any(Window, ['end', end_time, endTime])),
      DayOk = Days =:= [] orelse lists:member(DayOfWeek, Days),
      TimeOk =
        case {StartSec, EndSec} of
          {undefined, undefined} -> true;
          {Start, undefined} -> SecOfDay >= Start;
          {undefined, End} -> SecOfDay =< End;
          {Start, End} when Start =< End -> SecOfDay >= Start andalso SecOfDay =< End;
          {Start, End} -> SecOfDay >= Start orelse SecOfDay =< End
        end,
      DayOk andalso TimeOk
    end,
    Windows0
  );
within_active_windows(_Now, _OffsetSeconds, _Windows) -> true.

normalize_weekdays([]) -> [];
normalize_weekdays([Item | Rest]) ->
  [weekday_value(Item) | normalize_weekdays(Rest)];
normalize_weekdays(Value) ->
  [weekday_value(Value)].

weekday_value(V) when is_integer(V) -> clamp_range(V, 1, 7);
weekday_value(V0) ->
  case string:lowercase(to_bin(V0)) of
    <<"mon">> -> 1;
    <<"monday">> -> 1;
    <<"tue">> -> 2;
    <<"tuesday">> -> 2;
    <<"wed">> -> 3;
    <<"wednesday">> -> 3;
    <<"thu">> -> 4;
    <<"thursday">> -> 4;
    <<"fri">> -> 5;
    <<"friday">> -> 5;
    <<"sat">> -> 6;
    <<"saturday">> -> 6;
    <<"sun">> -> 7;
    <<"sunday">> -> 7;
    _ -> 1
  end.

interval_seconds(Interval0) ->
  Interval = ensure_map(Interval0),
  Value = int_or_default(find_any(Interval, [value]), 0),
  Unit = string:lowercase(to_bin(find_any(Interval, [unit]))),
  Multiplier =
    case Unit of
      <<"seconds">> -> 1;
      <<"second">> -> 1;
      <<"minutes">> -> 60;
      <<"minute">> -> 60;
      <<"hours">> -> 3600;
      <<"hour">> -> 3600;
      <<"days">> -> 86400;
      <<"day">> -> 86400;
      _ -> 0
    end,
  case Multiplier of
    0 -> undefined;
    _ -> Value * Multiplier
  end.

latest_run_anchor([]) -> undefined;
latest_run_anchor(Runs0) ->
  Runs = sort_by_created_at([ensure_map(R) || R <- Runs0]),
  case lists:reverse(Runs) of
    [Run | _] ->
      first_number([
        get_in_map(Run, [state, completed_at], undefined),
        get_in_map(Run, [state, started_at], undefined),
        get_in_map(Run, [audit, triggered_at], undefined),
        get_in_map(Run, [spec, planned_for_at], undefined)
      ]);
    [] ->
      undefined
  end.

timezone_offset_seconds(Policy0) ->
  Policy = ensure_map(Policy0),
  case get_bin(Policy, [utc_offset, utcOffset], undefined) of
    undefined -> offset_seconds_for_timezone(get_bin(Policy, [timezone], <<"Asia/Shanghai">>));
    Value -> offset_seconds(Value)
  end.

offset_seconds_for_timezone(Tz0) ->
  case string:lowercase(to_bin(Tz0)) of
    <<"utc">> -> 0;
    <<"etc/utc">> -> 0;
    <<"gmt">> -> 0;
    <<"asia/shanghai">> -> 8 * 3600;
    <<"asia/singapore">> -> 8 * 3600;
    <<"asia/tokyo">> -> 9 * 3600;
    <<"europe/london">> -> 0;
    <<"america/new_york">> -> -5 * 3600;
    <<"america/los_angeles">> -> -8 * 3600;
    Value -> offset_seconds(Value)
  end.

offset_seconds(<<Sign, H1, H2, $:, M1, M2>>) when (Sign =:= $+) orelse (Sign =:= $-) ->
  Hours = ((H1 - $0) * 10) + (H2 - $0),
  Minutes = ((M1 - $0) * 10) + (M2 - $0),
  Magnitude = (Hours * 3600) + (Minutes * 60),
  case Sign of
    $- -> -Magnitude;
    _ -> Magnitude
  end;
offset_seconds(_) ->
  8 * 3600.

now_ts() -> erlang:system_time(millisecond) / 1000.0.

date_of_ts(Ts) ->
  {Date, _Time} = unix_to_datetime(Ts),
  Date.

unix_to_datetime(Ts0) ->
  Ts = trunc(Ts0),
  Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
  calendar:gregorian_seconds_to_datetime(Epoch + Ts).

sort_by_created_at(Objs0) ->
  lists:sort(
    fun (A0, B0) ->
      A = ensure_map(A0),
      B = ensure_map(B0),
      get_in_map(A, [header, created_at], 0) =< get_in_map(B, [header, created_at], 0)
    end,
    Objs0
  ).

read_objects_in_dir(Dir) ->
  [read_json(Path) || Path <- json_files(Dir)].

json_files(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} -> [filename:join([Dir, Name]) || Name <- Names, filename:extension(Name) =:= ".json"];
    _ -> []
  end.

read_json(Path) ->
  case file:read_file(Path) of
    {ok, Bin} -> normalize_keys(openagentic_json:decode(Bin));
    _ -> #{}
  end.

normalize_keys(Map) when is_map(Map) ->
  maps:from_list([{normalize_key(K), normalize_keys(V)} || {K, V} <- maps:to_list(Map)]);
normalize_keys(List) when is_list(List) ->
  [normalize_keys(Item) || Item <- List];
normalize_keys(Other) -> Other.

normalize_key(K) when is_binary(K) -> binary_to_atom(K, utf8);
normalize_key(K) -> K.

id_of(Obj0) -> get_in_map(ensure_map(Obj0), [header, id], undefined).

first_number([]) -> undefined;
first_number([Value | _Rest]) when is_integer(Value); is_float(Value) -> Value;
first_number([_ | Rest]) -> first_number(Rest).

compact_map(Map0) -> maps:filter(fun (_K, V) -> V =/= undefined end, ensure_map(Map0)).

find_any(_Map, []) -> undefined;
find_any(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> find_any(Map, Rest);
    V -> V
  end.

get_in_map(Map0, [Key], Default) -> maps:get(Key, ensure_map(Map0), Default);
get_in_map(Map0, [Key | Rest], Default) ->
  case maps:get(Key, ensure_map(Map0), undefined) of
    undefined -> Default;
    Next -> get_in_map(Next, Rest, Default)
  end.

get_bin(Map0, [Key], Default) -> to_bin(maps:get(Key, ensure_map(Map0), Default));
get_bin(Map0, [Key | Rest], Default) ->
  case maps:get(Key, ensure_map(Map0), undefined) of
    undefined -> to_bin(Default);
    Next -> get_bin(Next, Rest, Default)
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(F) when is_float(F) -> list_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case catch binary_to_integer(string:trim(B)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case catch list_to_integer(string:trim(L)) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

clamp_range(Value, Min, Max) ->
  erlang:min(Max, erlang:max(Min, Value)).
