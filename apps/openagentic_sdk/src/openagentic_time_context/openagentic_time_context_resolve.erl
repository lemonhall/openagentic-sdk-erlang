-module(openagentic_time_context_resolve).

-export([from_opts/1, normalize/1, put_in_opts/2, resolve/1]).

-define(DEFAULT_TIMEZONE, <<"Asia/Shanghai">>).
-define(DEFAULT_UTC_OFFSET, <<"+08:00">>).
-define(DEFAULT_TIMEZONE_LABEL, <<"UTC+08:00 / 东八区"/utf8>>).

from_opts(Opts0) ->
  Opts = openagentic_time_context_utils:ensure_map(Opts0),
  case openagentic_time_context_utils:pick_opt(Opts, [time_context, timeContext, <<"time_context">>, <<"timeContext">>]) of
    undefined -> undefined;
    null -> undefined;
    Value -> normalize(Value)
  end.

resolve(Opts0) ->
  case from_opts(Opts0) of undefined -> default_context(); Context -> Context end.

put_in_opts(Opts0, TimeContext0) ->
  (openagentic_time_context_utils:ensure_map(Opts0))#{time_context => normalize(TimeContext0)}.

default_context() ->
  {LocalTime, UtcTime} = current_time_strings(?DEFAULT_UTC_OFFSET),
  normalize(#{timezone => ?DEFAULT_TIMEZONE, utc_offset => ?DEFAULT_UTC_OFFSET, timezone_label => ?DEFAULT_TIMEZONE_LABEL, current_local_time => LocalTime, current_utc_time => UtcTime}).

normalize(Context0) ->
  Context = openagentic_time_context_utils:ensure_map(Context0),
  Timezone = choose(Context, [timezone, <<"timezone">>], ?DEFAULT_TIMEZONE),
  UtcOffset = choose(Context, [utc_offset, <<"utc_offset">>, utcOffset, <<"utcOffset">>], ?DEFAULT_UTC_OFFSET),
  TimezoneLabel = choose(Context, [timezone_label, <<"timezone_label">>, timezoneLabel, <<"timezoneLabel">>], ?DEFAULT_TIMEZONE_LABEL),
  {DefaultLocalTime, DefaultUtcTime} = current_time_strings(UtcOffset),
  CurrentLocalTime = choose(Context, [current_local_time, <<"current_local_time">>, currentLocalTime, <<"currentLocalTime">>], DefaultLocalTime),
  CurrentUtcTime = choose(Context, [current_utc_time, <<"current_utc_time">>, currentUtcTime, <<"currentUtcTime">>], DefaultUtcTime),
  RelativeBasisDefault = iolist_to_binary([<<"Interpret relative time terms against local time ">>, CurrentLocalTime, <<" (">>, Timezone, <<", ">>, TimezoneLabel, <<") unless the user explicitly overrides it.">>]),
  RelativeBasis = choose(Context, [relative_time_basis, <<"relative_time_basis">>, relativeTimeBasis, <<"relativeTimeBasis">>], RelativeBasisDefault),
  #{timezone => openagentic_time_context_utils:to_bin(Timezone), utc_offset => openagentic_time_context_utils:to_bin(UtcOffset), timezone_label => openagentic_time_context_utils:to_bin(TimezoneLabel), current_local_time => openagentic_time_context_utils:to_bin(CurrentLocalTime), current_utc_time => openagentic_time_context_utils:to_bin(CurrentUtcTime), relative_time_basis => openagentic_time_context_utils:to_bin(RelativeBasis)}.

choose(Context, Keys, Default) ->
  openagentic_time_context_utils:first_non_blank([openagentic_time_context_utils:get_any(Context, Keys, undefined), Default]).

current_time_strings(UtcOffset0) ->
  UtcOffset = openagentic_time_context_utils:to_bin(UtcOffset0),
  Utc = calendar:universal_time(),
  Local = shift_datetime(Utc, offset_seconds(UtcOffset)),
  {format_datetime(Local, UtcOffset), format_datetime(Utc, <<"Z">>)}.

shift_datetime(DateTime, Seconds) ->
  calendar:gregorian_seconds_to_datetime(calendar:datetime_to_gregorian_seconds(DateTime) + Seconds).

offset_seconds(<<Sign, H1, H2, $:, M1, M2>>) when (Sign =:= $+) orelse (Sign =:= $-) ->
  Magnitude = (((H1 - $0) * 10) + (H2 - $0)) * 3600 + (((M1 - $0) * 10) + (M2 - $0)) * 60,
  case Sign of $- -> -Magnitude; _ -> Magnitude end;
offset_seconds(_) ->
  8 * 3600.

format_datetime({{Year, Month, Day}, {Hour, Minute, Second}}, Offset0) ->
  list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B~s", [Year, Month, Day, Hour, Minute, Second, openagentic_time_context_utils:to_list(openagentic_time_context_utils:to_bin(Offset0))])).
