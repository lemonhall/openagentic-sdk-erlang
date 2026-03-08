-module(openagentic_time_context_render).

-export([compose_system_prompt/2, marker/0, render_system_prompt/1]).

marker() ->
  <<"OPENAGENTIC_TIME_CONTEXT_V1">>.

render_system_prompt(TimeContext0) ->
  TimeContext = openagentic_time_context_resolve:normalize(TimeContext0),
  iolist_to_binary([
    marker(), <<"\n">>, <<"Time context (must follow):\n">>,
    <<"- User timezone: ">>, maps:get(timezone, TimeContext), <<"\n">>,
    <<"- User timezone label: ">>, maps:get(timezone_label, TimeContext), <<"\n">>,
    <<"- User UTC offset: ">>, maps:get(utc_offset, TimeContext), <<"\n">>,
    <<"- Current local time: ">>, maps:get(current_local_time, TimeContext), <<"\n">>,
    <<"- Current UTC time: ">>, maps:get(current_utc_time, TimeContext), <<"\n">>,
    <<"- Relative-time baseline: ">>, maps:get(relative_time_basis, TimeContext), <<"\n">>,
    <<"- When the task is time-sensitive, prefer absolute dates/times in the answer.\n\n">>,
    <<"中文补充（必须遵守）：\n"/utf8>>,
    <<"- 用户默认时区是 Asia/Shanghai（东八区 / UTC+08:00）。\n"/utf8>>,
    <<"- “今天 / 明天 / 昨天 / 最近 / 截至目前 / 本周 / 本月 / 当前”都以上述东八区时间快照为准。\n"/utf8>>,
    <<"- 不要自行猜测别的时区，也不要刷新另一套“现在”。\n"/utf8>>,
    <<"- 涉及时效性判断时，优先输出绝对日期或绝对时间。"/utf8>>
  ]).

compose_system_prompt(SystemPrompt0, TimeContext0) ->
  TimeBlock = render_system_prompt(TimeContext0),
  SystemPrompt = string:trim(openagentic_time_context_utils:to_bin(SystemPrompt0)),
  case SystemPrompt of
    <<>> -> TimeBlock;
    _ -> case binary:match(SystemPrompt, marker()) of nomatch -> iolist_to_binary([SystemPrompt, <<"\n\n">>, TimeBlock]); _ -> SystemPrompt end
  end.
