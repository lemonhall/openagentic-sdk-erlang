-module(openagentic_permissions_gate).

-export([bypass/0, deny/0, prompt/0, prompt/1, default/1]).

bypass() ->
  #{mode => bypass}.

deny() ->
  #{mode => deny}.

prompt() ->
  #{mode => prompt}.

prompt(UserAnswerer) ->
  gate_with_answerer(#{mode => prompt}, UserAnswerer).

default(UserAnswererOrUndefined) ->
  gate_with_answerer(#{mode => default}, UserAnswererOrUndefined).

gate_with_answerer(Gate, UserAnswerer) ->
  case UserAnswerer of
    F when is_function(F, 1) -> Gate#{user_answerer => F};
    _ -> Gate
  end.
