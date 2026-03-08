-module(openagentic_task_runners_compose).

-export([compose/1]).

compose(Runners0) ->
  Runners = openagentic_task_runners_utils:ensure_list(Runners0),
  fun (Agent0, Prompt0, Ctx0) ->
    Agent = openagentic_task_runners_utils:to_bin(Agent0),
    Prompt = openagentic_task_runners_utils:to_bin(Prompt0),
    Ctx = openagentic_task_runners_utils:ensure_map(Ctx0),
    compose_loop(Runners, Agent, Prompt, Ctx, undefined)
  end.

compose_loop([], _Agent, _Prompt, _Ctx, LastUnhandled) ->
  case LastUnhandled of undefined -> erlang:error({unhandled_agent, <<>>}); _ -> erlang:error(LastUnhandled) end;
compose_loop([Runner | Rest], Agent, Prompt, Ctx, _LastUnhandled) ->
  try Runner(Agent, Prompt, Ctx)
  catch
    error:{unhandled_agent, _} = Error -> compose_loop(Rest, Agent, Prompt, Ctx, Error);
    throw:{unhandled_agent, _} = Error -> compose_loop(Rest, Agent, Prompt, Ctx, Error)
  end.
