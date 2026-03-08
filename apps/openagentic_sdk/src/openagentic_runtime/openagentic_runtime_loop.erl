-module(openagentic_runtime_loop).
-export([run_loop/1]).

run_loop(State0) ->
  Steps = maps:get(steps, State0),
  Max = maps:get(max_steps, State0),
  case Steps >= Max of
    true ->
      openagentic_runtime_finalize:finalize_max_steps(State0);
    false ->
      case openagentic_runtime_model:call_model(State0) of
        {ok, ModelOut, State1} ->
          openagentic_runtime_model:handle_model_output(ModelOut, State1);
        {error, Reason, State1} ->
          openagentic_runtime_finalize:finalize_error(State1, Reason)
      end
  end.
