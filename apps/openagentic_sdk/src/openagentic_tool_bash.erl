-module(openagentic_tool_bash).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Bash">>.

description() -> <<"Run a shell command.">>.

run(Input0, Ctx0) -> openagentic_tool_bash_api:run(Input0, Ctx0).
