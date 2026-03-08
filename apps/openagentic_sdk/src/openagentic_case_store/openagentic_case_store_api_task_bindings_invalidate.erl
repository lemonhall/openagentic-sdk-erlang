-module(openagentic_case_store_api_task_bindings_invalidate).
-export([invalidate_credential_binding/2]).

invalidate_credential_binding(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TaskId = openagentic_case_store_common_lookup:required_bin(Input, [task_id, taskId]),
  BindingId = openagentic_case_store_common_lookup:required_bin(Input, [credential_binding_id, credentialBindingId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      BindingPath = openagentic_case_store_repo_paths:credential_binding_file(CaseDir, TaskId, BindingId),
      TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(BindingPath) andalso filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Binding0 = openagentic_case_store_repo_persist:read_json(BindingPath),
          case openagentic_case_store_task_auth_validation:maybe_check_expected_revision(Input, Binding0) of
            ok ->
              Now = openagentic_case_store_common_meta:now_ts(),
              Binding1 =
                openagentic_case_store_repo_persist:update_object(
                  Binding0,
                  Now,
                  fun (Obj) ->
                    Obj#{
                      state =>
                        maps:merge(
                          maps:get(state, Obj, #{}),
                          openagentic_case_store_common_meta:compact_map(
                            #{
                              status => openagentic_case_store_common_lookup:get_bin(Input, [status], <<"invalidated">>),
                              invalidated_at => Now
                            }
                          )
                        ),
                      audit =>
                        maps:merge(
                          maps:get(audit, Obj, #{}),
                          openagentic_case_store_common_meta:compact_map(
                            #{
                              updated_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                              invalidation_reason => openagentic_case_store_common_lookup:get_bin(Input, [reason], undefined),
                              note => openagentic_case_store_common_lookup:get_bin(Input, [note], undefined)
                            }
                          )
                        )
                    }
                  end
                ),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, BindingPath, Binding1),
              Task0 = openagentic_case_store_repo_persist:read_json(TaskPath),
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
            {error, Reason} -> {error, Reason}
          end
      end
  end.
