-module(openagentic_tool_webfetch).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"WebFetch">>.

description() -> <<"Fetch a URL over HTTP(S) and return a size-bounded representation.">>.

run(Input0, Ctx0) -> openagentic_tool_webfetch_api:run(Input0, Ctx0).
