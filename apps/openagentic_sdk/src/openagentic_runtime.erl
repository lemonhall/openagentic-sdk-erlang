-module(openagentic_runtime).
-export([query/2]).
query(Prompt, Opts) ->
  openagentic_runtime_query:query(Prompt, Opts).
