-module(openagentic_case_store_run_context).
-export([load_monitoring_task_context/3, resolve_task_version/2, load_task_version/3, run_task_error/3, retry_run_error/4, task_run_in_progress_error/2, task_workspace_dir/2, build_monitoring_run_context/3]).

load_monitoring_task_context(RootDir, CaseId, TaskId) ->
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} ->
      {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false ->
          {error, not_found};
        true ->
          Task0 = openagentic_case_store_repo_persist:read_json(TaskPath),
          Versions = openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId),
          CredentialBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
          case resolve_task_version(Task0, Versions) of
            undefined -> {error, no_task_version};
            Version -> {ok, CaseDir, Task0, Version, Versions, CredentialBindings}
          end
      end
  end.

resolve_task_version(Task0, Versions0) ->
  Versions = [openagentic_case_store_common_core:ensure_map(V) || V <- Versions0],
  ActiveVersionId = openagentic_case_store_common_lookup:get_in_map(Task0, [links, active_version_id], undefined),
  case [V || V <- Versions, openagentic_case_store_common_meta:id_of(V) =:= ActiveVersionId] of
    [Version | _] -> Version;
    [] ->
      case lists:reverse(Versions) of
        [Version | _] -> Version;
        [] -> undefined
      end
  end.

load_task_version(CaseDir, TaskId, undefined) ->
  resolve_task_version(#{links => #{}}, openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId));
load_task_version(CaseDir, TaskId, VersionId) ->
  Path = openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, VersionId),
  case filelib:is_file(Path) of
    true -> openagentic_case_store_repo_persist:read_json(Path);
    false -> resolve_task_version(#{links => #{}}, openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId))
  end.

run_task_error(Task, Versions, CredentialBindings) ->
  Authorization = openagentic_case_store_task_auth_resolve:build_task_authorization(Task, Versions, CredentialBindings),
  case openagentic_case_store_task_auth_validation:activation_error(Authorization) of
    undefined ->
      case openagentic_case_store_common_lookup:get_in_map(Task, [state, status], <<"active">>) of
        <<"active">> -> undefined;
        <<"ready_to_activate">> -> ready_to_activate;
        <<"rectification_required">> -> rectification_required;
        <<"paused">> -> paused;
        Other when Other =:= <<"awaiting_credentials">>; Other =:= <<"credential_expired">>; Other =:= <<"reauthorization_required">> -> Other;
        _ -> undefined
      end;
    Error -> Error
  end.

retry_run_error(Task, Run, Versions, CredentialBindings) ->
  case run_task_error(Task, Versions, CredentialBindings) of
    undefined ->
      case {openagentic_case_store_common_lookup:get_in_map(Run, [state, status], <<>>), openagentic_case_store_common_lookup:get_in_map(Run, [links, successful_attempt_id], undefined)} of
        {<<"running">>, _} -> run_in_progress;
        {_, SuccessfulAttemptId} when SuccessfulAttemptId =/= undefined -> run_already_completed;
        _ -> undefined
      end;
    Error -> Error
  end.

task_run_in_progress_error(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:to_bin(TaskId0),
  case lists:reverse(openagentic_case_store_repo_readers:read_task_runs(CaseDir, TaskId)) of
    [Run | _] ->
      case openagentic_case_store_common_lookup:get_in_map(Run, [state, status], <<>>) of
        <<"running">> -> run_in_progress;
        <<"scheduled">> -> run_in_progress;
        _ -> undefined
      end;
    [] ->
      undefined
  end.

task_workspace_dir(CaseDir, Task0) ->
  Task = openagentic_case_store_common_core:ensure_map(Task0),
  case openagentic_case_store_common_lookup:get_in_map(Task, [links, workspace_ref], undefined) of
    undefined -> CaseDir;
    Ref -> filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(Ref)])
  end.

build_monitoring_run_context(CaseDir, Task0, Version0) ->
  Task = openagentic_case_store_common_core:ensure_map(Task0),
  Version = openagentic_case_store_common_core:ensure_map(Version0),
  TaskId = openagentic_case_store_common_meta:id_of(Task),
  Versions = openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId),
  Runs = lists:reverse(openagentic_case_store_repo_readers:read_task_runs(CaseDir, TaskId)),
  Attempts = lists:reverse(openagentic_case_store_repo_readers:read_task_run_attempts(CaseDir, TaskId)),
  Reports = lists:reverse(openagentic_case_store_repo_readers:read_task_fact_reports(CaseDir, TaskId)),
  Briefs = lists:reverse(openagentic_case_store_repo_readers:read_task_exception_briefs(CaseDir, TaskId)),
  #{
    task_workspace_ref => openagentic_case_store_common_lookup:get_in_map(Task, [links, workspace_ref], undefined),
    current_task_version_id => openagentic_case_store_common_meta:id_of(Version),
    historical_version_summary => openagentic_case_store_task_history_versions:build_historical_version_summary(Versions),
    historical_execution_summary => openagentic_case_store_task_history_runs:build_historical_execution_summary(Runs, Attempts, Reports),
    latest_report_summary => openagentic_case_store_task_history_runs:build_latest_report_summary(Reports),
    latest_exception_summary => openagentic_case_store_task_history_runs:build_latest_exception_summary(Attempts, Briefs),
    recent_rectification_summary => openagentic_case_store_task_history_runs:build_recent_rectification_summary(Versions)
  }.
