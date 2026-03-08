-module(openagentic_case_store_api_task_detail).
-export([get_task_detail/3]).

get_task_detail(RootDir0, CaseId0, TaskId0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  CaseId = openagentic_case_store_common_core:to_bin(CaseId0),
  TaskId = openagentic_case_store_common_core:to_bin(TaskId0),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      TaskPath = openagentic_case_store_repo_paths:task_file(CaseDir, TaskId),
      case filelib:is_file(TaskPath) of
        false -> {error, not_found};
        true ->
          Task = openagentic_case_store_repo_persist:read_json(TaskPath),
          Versions = openagentic_case_store_repo_readers:read_task_versions(CaseDir, TaskId),
          CredentialBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
          Runs = lists:reverse(openagentic_case_store_repo_readers:read_task_runs(CaseDir, TaskId)),
          Attempts = lists:reverse(openagentic_case_store_repo_readers:read_task_run_attempts(CaseDir, TaskId)),
          Reports = lists:reverse(openagentic_case_store_repo_readers:read_task_fact_reports(CaseDir, TaskId)),
          Briefs = lists:reverse(openagentic_case_store_repo_readers:read_task_exception_briefs(CaseDir, TaskId)),
          Authorization = openagentic_case_store_task_auth_resolve:build_task_authorization(Task, Versions, CredentialBindings),
          FailureStats = openagentic_case_store_task_history_runs:build_task_failure_stats(Runs, Attempts),
          VersionSummary = openagentic_case_store_task_history_versions:build_historical_version_summary(Versions),
          ExecutionSummary = openagentic_case_store_task_history_runs:build_historical_execution_summary(Runs, Attempts, Reports),
          LatestExceptionSummary = openagentic_case_store_task_history_runs:build_latest_exception_summary(Attempts, Briefs),
          LatestReportSummary = openagentic_case_store_task_history_runs:build_latest_report_summary(Reports),
          RecentRectificationSummary = openagentic_case_store_task_history_runs:build_recent_rectification_summary(Versions),
          {ok,
           #{
              task => Task,
              versions => Versions,
              credential_bindings => CredentialBindings,
              authorization => Authorization,
              latest_version_diff => openagentic_case_store_task_history_versions:build_latest_version_diff(Versions, Authorization),
              runs => Runs,
              run_attempts => Attempts,
              fact_reports => Reports,
              exception_briefs => Briefs,
              failure_stats => FailureStats,
              historical_version_summary => VersionSummary,
              historical_execution_summary => ExecutionSummary,
              latest_exception_summary => LatestExceptionSummary,
              latest_report_summary => LatestReportSummary,
              recent_rectification_summary => RecentRectificationSummary,
              artifacts => openagentic_case_store_repo_readers:build_task_artifacts(Reports)
            }}
      end
  end.
