-module(openagentic_case_store_api_task_run).
-export([run_task/2, retry_run/2]).

run_task(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TaskId = openagentic_case_store_common_lookup:required_bin(Input, [task_id, taskId]),
  case openagentic_case_store_run_context:load_monitoring_task_context(RootDir, CaseId, TaskId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseDir, Task0, Version, Versions, CredentialBindings} ->
      case openagentic_case_store_common_meta:first_defined([openagentic_case_store_run_context:task_run_in_progress_error(CaseDir, TaskId), openagentic_case_store_run_context:run_task_error(Task0, Versions, CredentialBindings)]) of
        undefined ->
          Now = openagentic_case_store_common_meta:now_ts(),
          RunId = openagentic_case_store_common_meta:new_id(<<"run">>),
          Run0 = openagentic_case_store_run_build:build_monitoring_run(CaseId, TaskId, openagentic_case_store_common_meta:id_of(Version), RunId, Version, Input, Now),
          ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_file(CaseDir, TaskId, RunId), Run0),
          openagentic_case_store_run_execute:execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, undefined, Input);
        Error ->
          {error, Error}
      end
  end.

retry_run(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  TaskId = openagentic_case_store_common_lookup:required_bin(Input, [task_id, taskId]),
  RunId = openagentic_case_store_common_lookup:required_bin(Input, [run_id, runId]),
  case openagentic_case_store_run_context:load_monitoring_task_context(RootDir, CaseId, TaskId) of
    {error, Reason} -> {error, Reason};
    {ok, CaseDir, Task0, _CurrentVersion, Versions, CredentialBindings} ->
      RunPath = openagentic_case_store_repo_paths:run_file(CaseDir, TaskId, RunId),
      case filelib:is_file(RunPath) of
        false -> {error, not_found};
        true ->
          Run0 = openagentic_case_store_repo_persist:read_json(RunPath),
          case openagentic_case_store_run_context:retry_run_error(Task0, Run0, Versions, CredentialBindings) of
            undefined ->
              VersionId = openagentic_case_store_common_lookup:get_in_map(Run0, [links, task_version_id], undefined),
              Version = openagentic_case_store_run_context:load_task_version(CaseDir, TaskId, VersionId),
              PreviousAttemptId = openagentic_case_store_common_lookup:get_in_map(Run0, [links, latest_attempt_id], undefined),
              openagentic_case_store_run_execute:execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, PreviousAttemptId, Input);
            Error ->
              {error, Error}
          end
      end
  end.
