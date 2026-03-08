-module(openagentic_tool_glob).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Glob">>.

description() -> <<"Find files by glob pattern within the project workspace.">>.

run(Input, Ctx) ->
  openagentic_tool_glob_api:run(Input, Ctx).
