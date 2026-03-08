-module(openagentic_case_store_api_task_revise).
-export([revise_task/2, revise_task_with_session/6]).

revise_task(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TaskId = openagentic_case_store_common_lookup:required_bin(Input, [task_id, taskId]),
  GovernanceSessionId = openagentic_case_store_common_lookup:required_bin(Input, [governance_session_id, governanceSessionId]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Task0 = openagentic_case_store_repo_persist:read_json(TaskPath),
          case openagentic_case_store_task_auth_validation:maybe_check_expected_revision(Input, Task0) of
            ok ->
              case openagentic_case_store_common_lookup:get_in_map(Task0, [links, governance_session_id], <<>>) of
                <<>> -> {error, governance_session_missing};
                GovernanceSessionId ->
                  revise_task_with_session(RootDir, CaseId, CaseDir, Task0, Input, GovernanceSessionId);
                _ -> {error, governance_session_mismatch}
              end;
            {error, Reason} -> {error, Reason}
          end
      end
  end.

revise_task_with_session(RootDir, CaseId, CaseDir, Task0, Input, GovernanceSessionId) ->
  TaskId = openagentic_case_store_common_lookup:get_in_map(Task0, [header, id], <<>>),
  case lists:reverse(openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId)) of
    [] ->
      {error, no_task_version};
    [CurrentVersion0 | _] ->
      Now = openagentic_case_store_common_meta:now_ts(),
      CurrentVersionId = openagentic_case_store_common_meta:id_of(CurrentVersion0),
      NextVersionId = openagentic_case_store_common_meta:new_id(<<"version">>),
      CurrentVersion1 =
        openagentic_case_store_repo_persist:update_object(
          CurrentVersion0,
          Now,
          fun (Obj) ->
            Obj#{
              state => maps:merge(maps:get(state, Obj, #{}), #{status => <<"superseded">>, superseded_at => Now})
            }
          end
        ),
      NextVersion = openagentic_case_store_task_revise_build:build_revised_task_version(CaseId, TaskId, NextVersionId, CurrentVersion0, Input, GovernanceSessionId, Now),
      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, CurrentVersionId), CurrentVersion1),
      ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, NextVersionId), NextVersion),
      Task1Base =
        openagentic_case_store_repo_persist:update_object(
          Task0,
          Now,
          fun (Obj) ->
            Obj#{
              links => maps:merge(maps:get(links, Obj, #{}), #{active_version_id => NextVersionId}),
              audit =>
                maps:merge(
                  maps:get(audit, Obj, #{}),
                  openagentic_case_store_common_meta:compact_map(
                    #{
                      revised_at => Now,
                      revised_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
                      latest_governance_session_id => GovernanceSessionId,
                      latest_change_summary => openagentic_case_store_common_lookup:get_bin(Input, [change_summary, changeSummary], undefined)
                    }
                  )
                )
            }
          end
        ),
      {Task1, Authorization} = openagentic_case_store_task_auth_resolve:sync_task_authorization(CaseDir, Task1Base, Now),
      ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
      ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
      ok = openagentic_case_store_task_revise_build:append_governance_revision_event(RootDir, GovernanceSessionId, CaseId, TaskId, CurrentVersionId, NextVersionId, Input),
      {ok,
       #{
         task => Task1,
         task_version => NextVersion,
         authorization => Authorization,
         latest_version_diff => openagentic_case_store_task_history_versions:build_latest_version_diff(openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId), Authorization),
         overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
       }}
  end.
