-module(openagentic_tool_grep).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Grep">>.

description() -> <<"Search file contents with a regex.">>.

run(Input0, Ctx0) -> openagentic_tool_grep_api:run(Input0, Ctx0).
