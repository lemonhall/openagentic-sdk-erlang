-module(openagentic_runtime_query).
-export([query/2]).
query(Prompt0, Opts0) ->
  Prompt = iolist_to_binary(Prompt0),
  Opts = openagentic_runtime_utils:ensure_map(Opts0),
  TimeContext = openagentic_time_context:resolve(Opts),
  Opts1 = openagentic_time_context:put_in_opts(Opts, TimeContext),
  QueryCtx = openagentic_runtime_query_setup:prepare_query_context(Prompt, Opts1, TimeContext),
  case openagentic_runtime_query_state:resolve_resume_state(QueryCtx) of
    {error, Reason} ->
      {error, Reason};
    {ok, ReadyCtx} ->
      State0 = openagentic_runtime_query_state:init_query_state(ReadyCtx),
      openagentic_runtime_loop:run_loop(State0)
  end.
