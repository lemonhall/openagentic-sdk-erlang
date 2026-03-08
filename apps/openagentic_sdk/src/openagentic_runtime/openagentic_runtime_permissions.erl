-module(openagentic_runtime_permissions).
-export([effective_permission_gate/3,effective_user_answerer/2,gate_for_mode/2,normalize_permission_mode/1,maybe_prepend_system_prompt/2]).

effective_permission_gate(Opts0, Gate0, UserAnswerer0) ->
  Opts = openagentic_runtime_utils:ensure_map(Opts0),
  Gate = openagentic_runtime_utils:ensure_map(Gate0),

  ModeOverride0 =
    maps:get(
      permission_mode_override,
      Opts,
      maps:get(
        permissionModeOverride,
        Opts,
        maps:get(<<"permission_mode_override">>, Opts, maps:get(<<"permissionModeOverride">>, Opts, undefined))
      )
    ),
  SessionMode0 =
    maps:get(
      session_permission_mode,
      Opts,
      maps:get(
        sessionPermissionMode,
        Opts,
        maps:get(<<"session_permission_mode">>, Opts, maps:get(<<"sessionPermissionMode">>, Opts, undefined))
      )
    ),

  ModeOverride = normalize_permission_mode(ModeOverride0),
  SessionMode = normalize_permission_mode(SessionMode0),

  GateMode = maps:get(mode, Gate, default),
  DesiredMode =
    case ModeOverride of
      undefined ->
        case SessionMode of
          undefined -> GateMode;
          M2 -> M2
        end;
      M1 -> M1
    end,

  case DesiredMode =:= GateMode of
    true ->
      Gate;
    false ->
      UA = effective_user_answerer(Gate, UserAnswerer0),
      gate_for_mode(DesiredMode, UA)
  end.

effective_user_answerer(Gate, UserAnswerer0) ->
  case maps:get(user_answerer, Gate, undefined) of
    F when is_function(F, 1) -> F;
    _ ->
      case UserAnswerer0 of
        F2 when is_function(F2, 1) -> F2;
        _ -> undefined
      end
  end.

gate_for_mode(bypass, _UA) -> openagentic_permissions:bypass();
gate_for_mode(deny, _UA) -> openagentic_permissions:deny();
gate_for_mode(default, UA) -> openagentic_permissions:default(UA);
gate_for_mode(prompt, UA) -> openagentic_permissions:prompt(UA);
gate_for_mode(_, UA) -> openagentic_permissions:default(UA).

normalize_permission_mode(undefined) -> undefined;
normalize_permission_mode(null) -> undefined;
normalize_permission_mode(bypass) -> bypass;
normalize_permission_mode(deny) -> deny;
normalize_permission_mode(prompt) -> prompt;
normalize_permission_mode(default) -> default;
normalize_permission_mode(A) when is_atom(A) -> normalize_permission_mode(atom_to_binary(A, utf8));
normalize_permission_mode(L) when is_list(L) -> normalize_permission_mode(unicode:characters_to_binary(L, utf8));
normalize_permission_mode(B) when is_binary(B) ->
  S = string:lowercase(string:trim(B)),
  case S of
    <<>> -> undefined;
    <<"bypass">> -> bypass;
    <<"allow">> -> bypass;
    <<"yes">> -> bypass;
    <<"deny">> -> deny;
    <<"block">> -> deny;
    <<"prompt">> -> prompt;
    <<"ask">> -> prompt;
    <<"default">> -> default;
    _ -> undefined
  end;
normalize_permission_mode(_) -> undefined.

%% ---- provider input helpers ----

maybe_prepend_system_prompt(State0, InputItems0) ->
  InputItems = openagentic_runtime_utils:ensure_list(InputItems0),
  case maps:get(system_prompt, State0, undefined) of
    P when is_binary(P) ->
      P2 = string:trim(P),
      case byte_size(P2) > 0 of
        true -> [#{role => <<"system">>, content => P2} | InputItems];
        false -> InputItems
      end;
    _ ->
      InputItems
  end.

%% ---- error helpers ----
