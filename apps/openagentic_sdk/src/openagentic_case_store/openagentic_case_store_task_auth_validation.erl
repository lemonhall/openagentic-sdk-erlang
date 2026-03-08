-module(openagentic_case_store_task_auth_validation).
-export([required_credential_slots_from_versions/1, required_credential_slots/1, slot_name_from_requirement/1, binding_status_valid/1, binding_status_expired/1, activation_error/1, maybe_check_expected_revision/2, resolve_binding_context/4, find_binding_by_id/2, binding_defaults_from_existing/1]).

required_credential_slots_from_versions(Versions) ->
  case lists:reverse(Versions) of
    [Version | _] -> required_credential_slots(openagentic_case_store_common_lookup:get_in_map(Version, [spec, credential_requirements], #{}));
    [] -> []
  end.

required_credential_slots(Requirements0) ->
  Requirements = openagentic_case_store_common_core:ensure_map(Requirements0),
  case openagentic_case_store_common_lookup:get_bin(Requirements, [slot_name, slotName], undefined) of
    undefined ->
      RawSlots =
        case openagentic_case_store_common_lookup:find_any(Requirements, [required_slots, requiredSlots, slots]) of
          undefined -> [];
          Value when is_list(Value) -> Value;
          Value -> [Value]
        end,
      openagentic_case_store_common_core:unique_binaries([slot_name_from_requirement(Item) || Item <- RawSlots, slot_name_from_requirement(Item) =/= <<>>]);
    SlotName -> [SlotName]
  end.

slot_name_from_requirement(Item) when is_binary(Item) -> openagentic_case_store_common_core:trim_bin(Item);
slot_name_from_requirement(Item) when is_list(Item) -> openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(Item));
slot_name_from_requirement(Item0) ->
  Item = openagentic_case_store_common_core:ensure_map(Item0),
  openagentic_case_store_common_lookup:get_bin(Item, [slot_name, slotName, name], <<>>).

binding_status_valid(Binding) ->
  lists:member(openagentic_case_store_common_lookup:get_in_map(Binding, [state, status], <<>>), [<<"validated">>, <<"active">>, <<"ready">>, <<"bound">>]).

binding_status_expired(Binding) ->
  openagentic_case_store_common_lookup:get_in_map(Binding, [state, status], <<>>) =:= <<"expired">>.

activation_error(Authorization) ->
  case maps:get(status, Authorization, <<"active">>) of
    <<"awaiting_credentials">> -> awaiting_credentials;
    <<"credential_expired">> -> credential_expired;
    <<"reauthorization_required">> -> reauthorization_required;
    _ -> undefined
  end.

maybe_check_expected_revision(Input0, Obj0) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  Obj = openagentic_case_store_common_core:ensure_map(Obj0),
  case openagentic_case_store_common_lookup:find_any(Input, [expected_revision, expectedRevision]) of
    undefined -> ok;
    _ ->
      ExpectedRevision = openagentic_case_store_common_lookup:get_int(Input, [expected_revision, expectedRevision], undefined),
      CurrentRevision = openagentic_case_store_common_lookup:get_in_map(Obj, [header, revision], 0),
      case ExpectedRevision =:= CurrentRevision of
        true -> ok;
        false -> {error, {revision_conflict, CurrentRevision}}
      end
  end.

resolve_binding_context(Input0, ExistingBindings0, RotateBindingId, ExistingBindingId) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  ExistingBindings = [openagentic_case_store_common_core:ensure_map(Item) || Item <- ExistingBindings0],
  ContextBinding =
    case RotateBindingId of
      undefined -> find_binding_by_id(ExistingBindings, ExistingBindingId);
      _ -> find_binding_by_id(ExistingBindings, RotateBindingId)
    end,
  case ((RotateBindingId =/= undefined) orelse (ExistingBindingId =/= undefined)) andalso ContextBinding =:= undefined of
    true -> {error, not_found};
    false ->
      SlotName =
        case openagentic_case_store_common_lookup:get_bin(Input, [slot_name, slotName], undefined) of
          undefined -> openagentic_case_store_common_lookup:get_in_map(ContextBinding, [spec, slot_name], undefined);
          Value -> Value
        end,
      case SlotName of
        undefined -> {error, {missing_required_field, slot_name}};
        <<>> -> {error, {missing_required_field, slot_name}};
        _ -> {ok, SlotName, binding_defaults_from_existing(ContextBinding), ContextBinding}
      end
  end.

find_binding_by_id(_Bindings, undefined) -> undefined;
find_binding_by_id([], _BindingId) -> undefined;
find_binding_by_id([Binding | Rest], BindingId) ->
  case openagentic_case_store_common_meta:id_of(Binding) =:= BindingId of
    true -> Binding;
    false -> find_binding_by_id(Rest, BindingId)
  end.

binding_defaults_from_existing(undefined) -> #{};
binding_defaults_from_existing(Binding0) ->
  Binding = openagentic_case_store_common_core:ensure_map(Binding0),
  openagentic_case_store_common_meta:compact_map(
    #{
      slot_name => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, slot_name], undefined),
      binding_type => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, binding_type], undefined),
      provider => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, provider], undefined),
      material_ref => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, material_ref], undefined)
    }
  ).
