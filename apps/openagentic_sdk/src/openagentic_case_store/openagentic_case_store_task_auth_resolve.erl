-module(openagentic_case_store_task_auth_resolve).
-export([resolve_credential_binding_id/2, resolve_validated_at/2, sync_task_authorization/3, build_task_authorization/3]).

resolve_credential_binding_id(Input, ExistingBindings) ->
  case openagentic_case_store_common_lookup:get_bin(Input, [credential_binding_id, credentialBindingId], undefined) of
    undefined ->
      SlotName = openagentic_case_store_common_lookup:get_bin(Input, [slot_name, slotName], <<>>),
      Provider = openagentic_case_store_common_lookup:get_bin(Input, [provider], <<>>),
      BindingType = openagentic_case_store_common_lookup:get_bin(Input, [binding_type, bindingType], <<>>),
      case lists:filter(
             fun (Binding) ->
               openagentic_case_store_common_lookup:get_in_map(Binding, [spec, slot_name], <<>>) =:= SlotName andalso
                 openagentic_case_store_common_lookup:get_in_map(Binding, [spec, provider], <<>>) =:= Provider andalso
                 openagentic_case_store_common_lookup:get_in_map(Binding, [spec, binding_type], <<>>) =:= BindingType
             end,
             ExistingBindings
           ) of
        [Binding | _] -> openagentic_case_store_common_meta:id_of(Binding);
        [] -> openagentic_case_store_common_meta:new_id(<<"binding">>)
      end;
    BindingId -> BindingId
  end.

resolve_validated_at(Input, Now) ->
  resolve_validated_at(Input, Now, #{}).

resolve_validated_at(Input, Now, Existing) ->
  case openagentic_case_store_common_lookup:get_number(Input, [validated_at, validatedAt], undefined) of
    undefined ->
      case openagentic_case_store_common_lookup:get_bin(Input, [status], openagentic_case_store_common_lookup:get_in_map(Existing, [state, status], <<"validated">>)) of
        <<"validated">> ->
          case openagentic_case_store_common_lookup:get_in_map(Existing, [state, validated_at], undefined) of
            undefined -> Now;
            Value -> Value
          end;
        _ -> openagentic_case_store_common_lookup:get_in_map(Existing, [state, validated_at], undefined)
      end;
    Value -> Value
  end.

sync_task_authorization(CaseDir, Task0, Now) ->
  TaskId = openagentic_case_store_common_lookup:get_in_map(Task0, [header, id], <<>>),
  Versions = openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId),
  CredentialBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
  Authorization0 = build_task_authorization(Task0, Versions, CredentialBindings),
  Status0 = openagentic_case_store_common_lookup:get_in_map(Task0, [state, status], <<"active">>),
  NextStatus =
    case maps:get(status, Authorization0, <<"active">>) of
      <<"ready_to_activate">> when Status0 =:= <<"active">> -> <<"active">>;
      Value -> Value
    end,
  NextRefs = [openagentic_case_store_common_meta:id_of(Binding) || Binding <- CredentialBindings],
  Task1 =
    openagentic_case_store_repo_persist:update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{
          spec => maps:merge(maps:get(spec, Obj, #{}), #{credential_binding_refs => NextRefs}),
          state => maps:merge(maps:get(state, Obj, #{}), #{status => NextStatus, health => openagentic_case_store_common_meta:task_health_for_status(NextStatus)})
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), Task1),
  {Task1, Authorization0#{status => NextStatus}}.

build_task_authorization(Task, Versions, CredentialBindings) ->
  RequiredSlots = openagentic_case_store_task_auth_validation:required_credential_slots_from_versions(Versions),
  ValidSlots =
    openagentic_case_store_common_core:unique_binaries(
      [openagentic_case_store_common_lookup:get_in_map(Binding, [spec, slot_name], <<>>) || Binding <- CredentialBindings, openagentic_case_store_task_auth_validation:binding_status_valid(Binding)]
    ),
  ExpiredSlots =
    openagentic_case_store_common_core:unique_binaries(
      [openagentic_case_store_common_lookup:get_in_map(Binding, [spec, slot_name], <<>>) || Binding <- CredentialBindings, openagentic_case_store_task_auth_validation:binding_status_expired(Binding)]
    ),
  MissingSlots = [Slot || Slot <- RequiredSlots, not lists:member(Slot, ValidSlots)],
  CurrentStatus = openagentic_case_store_common_lookup:get_in_map(Task, [state, status], <<"active">>),
  WasActivated =
    openagentic_case_store_common_lookup:get_in_map(Task, [state, activated_at], undefined) =/= undefined orelse
      openagentic_case_store_common_lookup:get_in_map(Task, [audit, activated_at], undefined) =/= undefined,
  Status =
    case RequiredSlots of
      [] -> <<"active">>;
      _ when ExpiredSlots =/= [] -> <<"credential_expired">>;
      _ when MissingSlots =/= [], WasActivated -> <<"reauthorization_required">>;
      _ when MissingSlots =/= [] -> <<"awaiting_credentials">>;
      _ when CurrentStatus =:= <<"active">> -> <<"active">>;
      _ -> <<"ready_to_activate">>
    end,
  #{required_slots => RequiredSlots, valid_slots => ValidSlots, missing_slots => MissingSlots, expired_slots => ExpiredSlots, status => Status}.
