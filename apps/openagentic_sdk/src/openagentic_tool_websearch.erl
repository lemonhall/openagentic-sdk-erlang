-module(openagentic_tool_websearch).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"WebSearch">>.

description() ->
  <<"Search the web (Tavily backend; falls back to DuckDuckGo HTML when TAVILY_API_KEY is missing).">>.

run(Input0, Ctx0) -> openagentic_tool_websearch_api:run(Input0, Ctx0).
