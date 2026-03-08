-module(openagentic_tool_edit).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Edit">>.

description() -> <<"Apply a precise edit (string replace) to a file.">>.

run(Input, Ctx) ->
  openagentic_tool_edit_api:run(Input, Ctx).
