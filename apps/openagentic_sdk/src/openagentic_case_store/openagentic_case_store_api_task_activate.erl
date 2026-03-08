-module(openagentic_case_store_api_task_activate).
-export([activate_task/2]).

activate_task(RootDir0, Input0) ->
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
          Versions = openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId),
          CredentialBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
          Authorization = openagentic_case_store_task_auth_resolve:build_task_authorization(Task0, Versions, CredentialBindings),
          case openagentic_case_store_task_auth_validation:activation_error(Authorization) of
            undefined ->
              Task1 =
                openagentic_case_store_repo_persist:update_object(
                  Task0,
                  Now,
                  fun (Obj) ->
                    Obj#{
                      state =>
                        maps:merge(
                          maps:get(state, Obj, #{}),
                          #{status => <<"active">>, health => openagentic_case_store_common_meta:task_health_for_status(<<"active">>), activated_at => Now}
                        ),
                      audit =>
                        maps:merge(
                          maps:get(audit, Obj, #{}),
                          openagentic_case_store_common_meta:compact_map(
                            #{
                              activated_at => Now,
                              activated_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [activated_by_op_id, activatedByOpId], undefined)
                            }
                          )
                        )
                    }
                  end
                ),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, TaskPath, Task1),
              ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
              ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
              {ok,
               #{
                 task => Task1,
                 authorization => Authorization#{status => <<"active">>},
                 overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
               }};
            Error -> {error, Error}
          end
      end
  end.
