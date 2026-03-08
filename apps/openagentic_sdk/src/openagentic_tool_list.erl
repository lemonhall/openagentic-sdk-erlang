-module(openagentic_tool_list).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"List">>.

description() -> <<"List files under a directory.">>.

run(Input, Ctx) ->
  openagentic_tool_list_api:run(Input, Ctx).
