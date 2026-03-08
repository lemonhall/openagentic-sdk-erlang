-module(openagentic_case_scheduler_time).
-export([date_of_ts/1, interval_seconds/1, now_ts/0, parse_fixed_times/1, timezone_offset_seconds/1, unix_to_datetime/1, within_active_windows/3]).

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
  Item = openagentic_case_scheduler_utils:ensure_map(Item0),
  case Item of
    #{} when map_size(Item) > 0 ->
      Hour = openagentic_case_scheduler_utils:int_or_default(openagentic_case_scheduler_utils:find_any(Item, [hour]), 0),
      Minute = openagentic_case_scheduler_utils:int_or_default(openagentic_case_scheduler_utils:find_any(Item, [minute]), 0),
      openagentic_case_scheduler_utils:clamp_range(Hour, 0, 23) * 3600 + openagentic_case_scheduler_utils:clamp_range(Minute, 0, 59) * 60;
    _ ->
      Bin = string:trim(openagentic_case_scheduler_utils:to_bin(Item0)),
      case binary:split(Bin, <<":">>, [global]) of
        [HBin, MBin] -> openagentic_case_scheduler_utils:clamp_range(openagentic_case_scheduler_utils:int_or_default(HBin, 0), 0, 23) * 3600 + openagentic_case_scheduler_utils:clamp_range(openagentic_case_scheduler_utils:int_or_default(MBin, 0), 0, 59) * 60;
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
      Window = openagentic_case_scheduler_utils:ensure_map(Window0),
      Days = normalize_weekdays(openagentic_case_scheduler_utils:get_in_map(Window, [weekdays], openagentic_case_scheduler_utils:get_in_map(Window, [days], []))),
      StartSec = fixed_time_seconds(openagentic_case_scheduler_utils:find_any(Window, [start, start_time, startTime])),
      EndSec = fixed_time_seconds(openagentic_case_scheduler_utils:find_any(Window, ['end', end_time, endTime])),
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
normalize_weekdays([Item | Rest]) -> [weekday_value(Item) | normalize_weekdays(Rest)];
normalize_weekdays(Value) -> [weekday_value(Value)].

weekday_value(V) when is_integer(V) -> openagentic_case_scheduler_utils:clamp_range(V, 1, 7);
weekday_value(V0) ->
  case string:lowercase(openagentic_case_scheduler_utils:to_bin(V0)) of
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
  Interval = openagentic_case_scheduler_utils:ensure_map(Interval0),
  Value = openagentic_case_scheduler_utils:int_or_default(openagentic_case_scheduler_utils:find_any(Interval, [value]), 0),
  Unit = string:lowercase(openagentic_case_scheduler_utils:to_bin(openagentic_case_scheduler_utils:find_any(Interval, [unit]))),
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
  case Multiplier of 0 -> undefined; _ -> Value * Multiplier end.

timezone_offset_seconds(Policy0) ->
  Policy = openagentic_case_scheduler_utils:ensure_map(Policy0),
  case openagentic_case_scheduler_utils:get_bin(Policy, [utc_offset, utcOffset], undefined) of
    undefined -> offset_seconds_for_timezone(openagentic_case_scheduler_utils:get_bin(Policy, [timezone], <<"Asia/Shanghai">>));
    Value -> offset_seconds(Value)
  end.

offset_seconds_for_timezone(Tz0) ->
  case string:lowercase(openagentic_case_scheduler_utils:to_bin(Tz0)) of
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
  case Sign of $- -> -Magnitude; _ -> Magnitude end;
offset_seconds(_) -> 8 * 3600.

now_ts() -> erlang:system_time(millisecond) / 1000.0.

date_of_ts(Ts) ->
  {Date, _Time} = unix_to_datetime(Ts),
  Date.

unix_to_datetime(Ts0) ->
  Ts = trunc(Ts0),
  Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
  calendar:gregorian_seconds_to_datetime(Epoch + Ts).
