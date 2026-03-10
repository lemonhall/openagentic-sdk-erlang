-module(openagentic_case_store_repo_paths).
-export([case_dir/2, case_file/1, round_file/2, candidate_file/2, task_file/2, task_version_file/3, credential_binding_file/3, run_file/3, run_attempt_file/3, fact_report_file/3, exception_brief_file/3, observation_pack_file/2, inspection_review_file/2, reconsideration_package_file/2, operation_file/2, timeline_file/1, attempt_scratch_ref/3, deliverables_dir/3, deliverable_ref/3, task_history_file/2, template_file/2, template_history_file/2, case_history_file/1, object_type_registry_file/1, mail_file/2, ensure_case_layout/1, ensure_dirs/1]).

case_dir(RootDir, CaseId0) ->
  CaseId = openagentic_case_store_common_core:ensure_list(CaseId0),
  filename:join([RootDir, "cases", CaseId]).

case_file(CaseDir) -> filename:join([CaseDir, "meta", "case.json"]).

round_file(CaseDir, RoundId0) ->
  RoundId = openagentic_case_store_common_core:ensure_list(RoundId0),
  filename:join([CaseDir, "meta", "rounds", RoundId ++ ".json"]).

candidate_file(CaseDir, CandidateId0) ->
  CandidateId = openagentic_case_store_common_core:ensure_list(CandidateId0),
  filename:join([CaseDir, "meta", "candidates", CandidateId ++ ".json"]).

task_file(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "task.json"]).

task_version_file(CaseDir, TaskId0, VersionId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  VersionId = openagentic_case_store_common_core:ensure_list(VersionId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "versions", VersionId ++ ".json"]).

credential_binding_file(CaseDir, TaskId0, BindingId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  BindingId = openagentic_case_store_common_core:ensure_list(BindingId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "credential_bindings", BindingId ++ ".json"]).

run_file(CaseDir, TaskId0, RunId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  RunId = openagentic_case_store_common_core:ensure_list(RunId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "runs", RunId ++ ".json"]).

run_attempt_file(CaseDir, TaskId0, AttemptId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  AttemptId = openagentic_case_store_common_core:ensure_list(AttemptId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "attempts", AttemptId ++ ".json"]).

fact_report_file(CaseDir, TaskId0, ReportId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  ReportId = openagentic_case_store_common_core:ensure_list(ReportId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "reports", ReportId ++ ".json"]).

exception_brief_file(CaseDir, TaskId0, BriefId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  BriefId = openagentic_case_store_common_core:ensure_list(BriefId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "briefs", BriefId ++ ".json"]).

observation_pack_file(CaseDir, PackId0) ->
  PackId = openagentic_case_store_common_core:ensure_list(PackId0),
  filename:join([CaseDir, "meta", "packs", PackId ++ ".json"]).

inspection_review_file(CaseDir, ReviewId0) ->
  ReviewId = openagentic_case_store_common_core:ensure_list(ReviewId0),
  filename:join([CaseDir, "meta", "inspection_reviews", ReviewId ++ ".json"]).

reconsideration_package_file(CaseDir, PackageId0) ->
  PackageId = openagentic_case_store_common_core:ensure_list(PackageId0),
  filename:join([CaseDir, "meta", "reconsideration_packages", PackageId ++ ".json"]).

operation_file(CaseDir, OperationId0) ->
  OperationId = openagentic_case_store_common_core:ensure_list(OperationId0),
  filename:join([CaseDir, "meta", "ops", OperationId ++ ".json"]).

timeline_file(CaseDir) -> filename:join([CaseDir, "meta", "timeline.jsonl"]).

attempt_scratch_ref(TaskId0, RunId0, AttemptId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  RunId = openagentic_case_store_common_core:ensure_list(RunId0),
  AttemptId = openagentic_case_store_common_core:ensure_list(AttemptId0),
  iolist_to_binary(["runs/", TaskId, "/", RunId, "/attempts/", AttemptId, "/scratch"]).

deliverables_dir(CaseDir, TaskId0, RunId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  RunId = openagentic_case_store_common_core:ensure_list(RunId0),
  filename:join([CaseDir, "artifacts", "tasks", TaskId, "runs", RunId]).

deliverable_ref(TaskId0, RunId0, FileName0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  RunId = openagentic_case_store_common_core:ensure_list(RunId0),
  FileName = openagentic_case_store_common_core:ensure_list(FileName0),
  iolist_to_binary(["artifacts/tasks/", TaskId, "/runs/", RunId, "/", FileName]).

task_history_file(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  filename:join([CaseDir, "meta", "tasks", TaskId, "history.jsonl"]).

template_file(CaseDir, TemplateId0) ->
  TemplateId = openagentic_case_store_common_core:ensure_list(TemplateId0),
  filename:join([CaseDir, "meta", "templates", TemplateId, "template.json"]).

template_history_file(CaseDir, TemplateId0) ->
  TemplateId = openagentic_case_store_common_core:ensure_list(TemplateId0),
  filename:join([CaseDir, "meta", "templates", TemplateId, "history.jsonl"]).

case_history_file(CaseDir) -> filename:join([CaseDir, "meta", "history.jsonl"]).

object_type_registry_file(CaseDir) -> filename:join([CaseDir, "meta", "object-type-registry.json"]).

mail_file(CaseDir, MailId0) ->
  MailId = openagentic_case_store_common_core:ensure_list(MailId0),
  filename:join([CaseDir, "meta", "mail", MailId ++ ".json"]).

ensure_case_layout(CaseDir) ->
  ensure_dirs(
    [
      filename:join([CaseDir, "meta", "rounds"]),
      filename:join([CaseDir, "meta", "candidates"]),
      filename:join([CaseDir, "meta", "tasks"]),
      filename:join([CaseDir, "meta", "templates"]),
      filename:join([CaseDir, "meta", "mail"]),
      filename:join([CaseDir, "meta", "packs"]),
      filename:join([CaseDir, "meta", "inspection_reviews"]),
      filename:join([CaseDir, "meta", "reconsideration_packages"]),
      filename:join([CaseDir, "meta", "ops"]),
      filename:join([CaseDir, "meta", "indexes"]),
      filename:join([CaseDir, "artifacts"]),
      filename:join([CaseDir, "workspaces"]),
      filename:join([CaseDir, "workspaces", "templates"]),
      filename:join([CaseDir, "published"])
    ]
  ).

ensure_dirs([]) -> ok;
ensure_dirs([Dir | Rest]) ->
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  ensure_dirs(Rest).
