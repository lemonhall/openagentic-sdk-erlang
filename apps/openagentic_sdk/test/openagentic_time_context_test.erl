-module(openagentic_time_context_test).

-include_lib("eunit/include/eunit.hrl").

default_time_context_uses_utf8_timezone_label_test() ->
  Ctx = openagentic_time_context:resolve(#{}),
  ?assertEqual(<<"Asia/Shanghai">>, maps:get(timezone, Ctx)),
  ?assertEqual(<<"+08:00">>, maps:get(utc_offset, Ctx)),
  ?assertEqual(<<"UTC+08:00 / 东八区"/utf8>>, maps:get(timezone_label, Ctx)),
  ok.

system_prompt_contains_utf8_timezone_label_test() ->
  Prompt = openagentic_time_context:render_system_prompt(openagentic_time_context:resolve(#{})),
  ?assert(binary:match(Prompt, <<"OPENAGENTIC_TIME_CONTEXT_V1">>) =/= nomatch),
  ?assert(binary:match(Prompt, <<"UTC+08:00 / 东八区"/utf8>>) =/= nomatch),
  ok.

compose_system_prompt_does_not_duplicate_marker_test() ->
  TimeBlock = openagentic_time_context:render_system_prompt(openagentic_time_context:resolve(#{})),
  Prompt = openagentic_time_context:compose_system_prompt(TimeBlock, #{}),
  ?assertEqual(TimeBlock, Prompt),
  ok.
