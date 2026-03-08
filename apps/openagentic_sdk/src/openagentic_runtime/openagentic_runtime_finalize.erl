-module(openagentic_runtime_finalize).
-export([finalize_error/2,finalize_max_steps/1,bump_steps/1]).

finalize_error(State0, Reason) ->
  Sid = maps:get(session_id, State0, <<>>),
  Steps = maps:get(steps, State0, 0),
  Provider = maps:get(provider_mod, State0, undefined),
  Phase = openagentic_runtime_errors:error_phase(Reason),
  ErrType = openagentic_runtime_errors:error_type(Reason),
  ErrMsg = openagentic_runtime_errors:error_message(State0, Reason),
  State1 = openagentic_runtime_events:append_event(State0, openagentic_events:runtime_error(Phase, ErrType, ErrMsg, openagentic_runtime_utils:to_bin(Provider), undefined)),
  State2 =
    openagentic_runtime_events:append_event(
      State1,
      openagentic_events:result(
        <<>>,
        Sid,
        <<"error">>,
        undefined,
        maps:get(previous_response_id, State0, undefined),
        undefined,
        Steps
      )
    ),
  {error, {runtime_error, Reason, maps:get(session_id, State2)}}.

finalize_max_steps(State0) ->
  Sid = maps:get(session_id, State0, <<>>),
  Steps = maps:get(steps, State0, 0),
  RespId = maps:get(previous_response_id, State0, undefined),
  State1 =
    openagentic_runtime_events:append_event(
      State0,
      openagentic_events:result(
        <<>>,
        Sid,
        <<"max_steps">>,
        undefined,
        RespId,
        undefined,
        Steps
      )
    ),
  {ok, #{session_id => maps:get(session_id, State1), final_text => <<>>}}.

bump_steps(State0) ->
  Steps = maps:get(steps, State0, 0),
  State0#{steps := Steps + 1}.
