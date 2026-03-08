-module(openagentic_tool_read).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Read">>.

description() -> <<"Read a text file. Supports line-based offset/limit.">>.

run(Input0, Ctx0) -> openagentic_tool_read_api:run(Input0, Ctx0).
