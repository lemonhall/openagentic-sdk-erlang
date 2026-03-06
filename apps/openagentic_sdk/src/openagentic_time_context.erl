-module(openagentic_time_context).

-export([
  marker/0,
  from_opts/1,
  resolve/1,
  put_in_opts/2,
  render_system_prompt/1,
  compose_system_prompt/2
]).

-define(DEFAULT_TIMEZONE, <<"Asia/Shanghai">>).
-define(DEFAULT_UTC_OFFSET, <<"+08:00">>).
-define(DEFAULT_TIMEZONE_LABEL, <<"UTC+08:00 / 东八区">>).

marker() ->
  <<"OPENAGENTIC_TIME_CONTEXT_V1">>.

from_opts(Opts0) ->
  Opts = ensure_map(Opts0),
  case pick_opt(Opts, [time_context, timeContext, <<"time_context">>, <<"timeContext">>]) of
    undefined -> undefined;
    null -> undefined;
    Value -> normalize(Value)
  end.

resolve(Opts0) ->
  case from_opts(Opts0) of
    undefined -> default_context();
    Ctx -> Ctx
  end.

put_in_opts(Opts0, TimeContext0) ->
  Opts = ensure_map(Opts0),
  TimeContext = normalize(TimeContext0),
  Opts#{time_context => TimeContext}.

render_system_prompt(TimeContext0) ->
  TimeContext = normalize(TimeContext0),
  Timezone = maps:get(timezone, TimeContext),
  UtcOffset = maps:get(utc_offset, TimeContext),
  TimezoneLabel = maps:get(timezone_label, TimeContext),
  LocalTime = maps:get(current_local_time, TimeContext),
  UtcTime = maps:get(current_utc_time, TimeContext),
  RelativeBasis = maps:get(relative_time_basis, TimeContext),
  iolist_to_binary([
    marker(),
    <<"\n">>,
    <<"Time context (must follow):\n">>,
    <<"- User timezone: ">>, Timezone, <<"\n">>,
    <<"- User timezone label: ">>, TimezoneLabel, <<"\n">>,
    <<"- User UTC offset: ">>, UtcOffset, <<"\n">>,
    <<"- Current local time: ">>, LocalTime, <<"\n">>,
    <<"- Current UTC time: ">>, UtcTime, <<"\n">>,
    <<"- Relative-time baseline: ">>, RelativeBasis, <<"\n">>,
    <<"- When the task is time-sensitive, prefer absolute dates/times in the answer.\n\n">>,
    <<"中文补充（必须遵守）：\n"/utf8>>,
    <<"- 用户默认时区是 Asia/Shanghai（东八区 / UTC+08:00）。\n"/utf8>>,
    <<"- “今天 / 明天 / 昨天 / 最近 / 截至目前 / 本周 / 本月 / 当前”都以上述东八区时间快照为准。\n"/utf8>>,
    <<"- 不要自行猜测别的时区，也不要刷新另一套“现在”。\n"/utf8>>,
    <<"- 涉及时效性判断时，优先输出绝对日期或绝对时间。"/utf8>>
  ]).

compose_system_prompt(SystemPrompt0, TimeContext0) ->
  TimeBlock = render_system_prompt(TimeContext0),
  SystemPrompt = string:trim(to_bin(SystemPrompt0)),
  case SystemPrompt of
    <<>> ->
      TimeBlock;
    _ ->
      case binary:match(SystemPrompt, marker()) of
        nomatch -> iolist_to_binary([SystemPrompt, <<"\n\n">>, TimeBlock]);
        _ -> SystemPrompt
      end
  end.

default_context() ->
  {LocalTime, UtcTime} = current_time_strings(?DEFAULT_UTC_OFFSET),
  normalize(#{
    timezone => ?DEFAULT_TIMEZONE,
    utc_offset => ?DEFAULT_UTC_OFFSET,
    timezone_label => ?DEFAULT_TIMEZONE_LABEL,
    current_local_time => LocalTime,
    current_utc_time => UtcTime
  }).

normalize(Context0) ->
  Context = ensure_map(Context0),
  Timezone = first_non_blank([get_any(Context, [timezone, <<"timezone">>], undefined), ?DEFAULT_TIMEZONE]),
  UtcOffset = first_non_blank([get_any(Context, [utc_offset, <<"utc_offset">>, utcOffset, <<"utcOffset">>], undefined), ?DEFAULT_UTC_OFFSET]),
  TimezoneLabel =
    first_non_blank([
      get_any(Context, [timezone_label, <<"timezone_label">>, timezoneLabel, <<"timezoneLabel">>], undefined),
      ?DEFAULT_TIMEZONE_LABEL
    ]),
  {DefaultLocalTime, DefaultUtcTime} = current_time_strings(UtcOffset),
  CurrentLocalTime =
    first_non_blank([
      get_any(Context, [current_local_time, <<"current_local_time">>, currentLocalTime, <<"currentLocalTime">>], undefined),
      DefaultLocalTime
    ]),
  CurrentUtcTime =
    first_non_blank([
      get_any(Context, [current_utc_time, <<"current_utc_time">>, currentUtcTime, <<"currentUtcTime">>], undefined),
      DefaultUtcTime
    ]),
  RelativeBasisDefault =
    iolist_to_binary([
      <<"Interpret relative time terms against local time ">>,
      CurrentLocalTime,
      <<" (">>, Timezone, <<", ">>, TimezoneLabel,
      <<") unless the user explicitly overrides it.">>
    ]),
  RelativeBasis =
    first_non_blank([
      get_any(Context, [relative_time_basis, <<"relative_time_basis">>, relativeTimeBasis, <<"relativeTimeBasis">>], undefined),
      RelativeBasisDefault
    ]),
  #{
    timezone => to_bin(Timezone),
    utc_offset => to_bin(UtcOffset),
    timezone_label => to_bin(TimezoneLabel),
    current_local_time => to_bin(CurrentLocalTime),
    current_utc_time => to_bin(CurrentUtcTime),
    relative_time_basis => to_bin(RelativeBasis)
  }.

current_time_strings(UtcOffset0) ->
  UtcOffset = to_bin(UtcOffset0),
  Utc = calendar:universal_time(),
  Local = shift_datetime(Utc, offset_seconds(UtcOffset)),
  {format_datetime(Local, UtcOffset), format_datetime(Utc, <<"Z">>)}.

shift_datetime(DateTime, Seconds) ->
  GregorianSeconds = calendar:datetime_to_gregorian_seconds(DateTime),
  calendar:gregorian_seconds_to_datetime(GregorianSeconds + Seconds).

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

format_datetime({{Y, Mo, D}, {H, Mi, S}}, Offset0) ->
  Offset = to_bin(Offset0),
  list_to_binary(
    io_lib:format(
      "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B~s",
      [Y, Mo, D, H, Mi, S, to_list(Offset)]
    )
  ).

pick_opt(_Map, []) ->
  undefined;
pick_opt(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_opt(Map, Rest);
    V -> V
  end.

get_any(_Map, [], Default) ->
  Default;
get_any(Map, [K | Rest], Default) ->
  case maps:get(K, Map, undefined) of
    undefined -> get_any(Map, Rest, Default);
    V -> V
  end.

first_non_blank([]) ->
  <<>>;
first_non_blank([V | Rest]) ->
  Bin = string:trim(to_bin(V)),
  case Bin of
    <<>> -> first_non_blank(Rest);
    <<"undefined">> -> first_non_blank(Rest);
    _ -> Bin
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(undefined) -> "";
to_list(B) when is_binary(B) -> unicode:characters_to_list(B, utf8);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(I) when is_integer(I) -> integer_to_list(I);
to_list(Other) -> io_lib:format("~p", [Other]).
