-module(openagentic_time_context).

-export([compose_system_prompt/2, from_opts/1, marker/0, put_in_opts/2, render_system_prompt/1, resolve/1]).

marker() -> openagentic_time_context_render:marker().
from_opts(Opts0) -> openagentic_time_context_resolve:from_opts(Opts0).
resolve(Opts0) -> openagentic_time_context_resolve:resolve(Opts0).
put_in_opts(Opts0, TimeContext0) -> openagentic_time_context_resolve:put_in_opts(Opts0, TimeContext0).
render_system_prompt(TimeContext0) -> openagentic_time_context_render:render_system_prompt(TimeContext0).
compose_system_prompt(SystemPrompt0, TimeContext0) -> openagentic_time_context_render:compose_system_prompt(SystemPrompt0, TimeContext0).
