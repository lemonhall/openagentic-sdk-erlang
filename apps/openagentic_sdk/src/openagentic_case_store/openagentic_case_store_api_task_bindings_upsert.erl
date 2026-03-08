-module(openagentic_case_store_api_task_bindings_upsert).
-export([upsert_credential_binding/2]).

upsert_credential_binding(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TaskId = openagentic_case_store_common_lookup:required_bin(Input, [task_id, taskId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Now = openagentic_case_store_common_meta:now_ts(),
          Task0 = openagentic_case_store_repo_persist:read_json(TaskPath),
          ExistingBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
          RotateBindingId = openagentic_case_store_common_lookup:get_bin(Input, [rotate_binding_id, rotateBindingId], undefined),
          ExistingBindingId = openagentic_case_store_common_lookup:get_bin(Input, [credential_binding_id, credentialBindingId], undefined),
          case openagentic_case_store_task_auth_validation:resolve_binding_context(Input, ExistingBindings, RotateBindingId, ExistingBindingId) of
            {error, Reason} -> {error, Reason};
            {ok, SlotName, BindingDefaults, ExistingBinding0} ->
              case ExistingBinding0 =:= undefined orelse openagentic_case_store_task_auth_validation:maybe_check_expected_revision(Input, ExistingBinding0) =:= ok of
                false -> openagentic_case_store_task_auth_validation:maybe_check_expected_revision(Input, ExistingBinding0);
                true ->
                  case RotateBindingId of
                    undefined ->
                      BindingId =
                        case ExistingBinding0 of
                          undefined -> openagentic_case_store_task_auth_resolve:resolve_credential_binding_id(Input, ExistingBindings);
                          _ -> openagentic_case_store_common_meta:id_of(ExistingBinding0)
                        end,
                      BindingPath = openagentic_case_store_repo_paths:credential_binding_file(CaseDir, TaskId, BindingId),
                      BindingInput = maps:merge(BindingDefaults, Input),
                      Binding1 =
                        case ExistingBinding0 of
                          undefined -> openagentic_case_store_task_auth_build:build_credential_binding(CaseId, TaskId, BindingId, BindingInput, SlotName, Now);
                          _ -> openagentic_case_store_task_auth_build:update_credential_binding(ExistingBinding0, BindingInput, SlotName, Now)
                        end,
                      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, BindingPath, Binding1),
                      {Task1, Authorization} = openagentic_case_store_task_auth_resolve:sync_task_authorization(CaseDir, Task0, Now),
                      ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
                      ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
                      {ok,
                       #{
                         credential_binding => Binding1,
                         credential_bindings => openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
                         task => Task1,
                         authorization => Authorization,
                         overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
                       }};
                    _ ->
                      RotatedFrom = ExistingBinding0,
                      BindingId = openagentic_case_store_common_meta:new_id(<<"binding">>),
                      BindingInput = maps:merge(BindingDefaults, Input),
                      RotatedFromPath = openagentic_case_store_repo_paths:credential_binding_file(CaseDir, TaskId, openagentic_case_store_common_meta:id_of(RotatedFrom)),
                      BindingPath = openagentic_case_store_repo_paths:credential_binding_file(CaseDir, TaskId, BindingId),
                      RotatedOld =
                        openagentic_case_store_repo_persist:update_object(
                          RotatedFrom,
                          Now,
                          fun (Obj) ->
                            Obj#{
                              links => maps:merge(maps:get(links, Obj, #{}), #{rotated_to_binding_id => BindingId}),
                              state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"rotated">>, rotated_at => Now}),
                              audit =>
                                maps:merge(
                                  maps:get(audit, Obj, #{}),
                                  openagentic_case_store_common_meta:compact_map(
                                    #{
                                      updated_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                                      note => openagentic_case_store_common_lookup:get_bin(Input, [note], undefined)
                                    }
                                  )
                                )
                            }
                          end
                        ),
                      RotatedNew0 = openagentic_case_store_task_auth_build:build_credential_binding(CaseId, TaskId, BindingId, BindingInput, SlotName, Now),
                      RotatedNew =
                        openagentic_case_store_repo_persist:update_object(
                          RotatedNew0,
                          Now,
                          fun (Obj) ->
                            Obj#{
                              links => maps:merge(maps:get(links, Obj, #{}), #{rotated_from_binding_id => openagentic_case_store_common_meta:id_of(RotatedFrom)})
                            }
                          end
                        ),
                      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, RotatedFromPath, RotatedOld),
                      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, BindingPath, RotatedNew),
                      {Task1, Authorization} = openagentic_case_store_task_auth_resolve:sync_task_authorization(CaseDir, Task0, Now),
                      ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
                      ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
                      {ok,
                       #{
                         credential_binding => RotatedNew,
                         credential_bindings => openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
                         task => Task1,
                         authorization => Authorization,
                         overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
                       }}
                  end
              end
          end
      end
  end.
