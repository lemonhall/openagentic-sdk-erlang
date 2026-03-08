-module(openagentic_case_store_repo_readers).
-export([sort_by_created_at/1, read_task_objects/1, read_template_objects/1, read_task_versions/2, read_task_credential_bindings/2, read_task_runs/2, read_task_run_attempts/2, read_task_fact_reports/2, read_task_exception_briefs/2, build_task_artifacts/1, read_objects_in_dir/1, json_files/1, safe_list_dir/1, load_case/2]).

sort_by_created_at(Objs) ->
  lists:sort(
    fun (A, B) ->
      openagentic_case_store_common_lookup:get_in_map(A, [header, created_at], 0) =< openagentic_case_store_common_lookup:get_in_map(B, [header, created_at], 0)
    end,
    Objs
  ).

read_task_objects(TaskRoot) ->
  TaskDirs = safe_list_dir(TaskRoot),
  lists:foldl(
    fun (Name, Acc) ->
      Path = filename:join([TaskRoot, Name, "task.json"]),
      case filelib:is_file(Path) of
        true -> [openagentic_case_store_repo_persist:read_json(Path) | Acc];
        false -> Acc
      end
    end,
    [],
    TaskDirs
  ).

read_template_objects(TemplateRoot) ->
  TemplateDirs = safe_list_dir(TemplateRoot),
  lists:foldl(
    fun (Name, Acc) ->
      Path = filename:join([TemplateRoot, Name, "template.json"]),
      case filelib:is_file(Path) of
        true -> [openagentic_case_store_repo_persist:read_json(Path) | Acc];
        false -> Acc
      end
    end,
    [],
    TemplateDirs
  ).

read_task_versions(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "versions"]))).

read_task_credential_bindings(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "credential_bindings"]))).

read_task_runs(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "runs"]))).

read_task_run_attempts(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "attempts"]))).

read_task_fact_reports(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "reports"]))).

read_task_exception_briefs(CaseDir, TaskId0) ->
  TaskId = openagentic_case_store_common_core:ensure_list(TaskId0),
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "tasks", TaskId, "briefs"]))).

build_task_artifacts(Reports0) ->
  Reports = [openagentic_case_store_common_core:ensure_map(Report) || Report <- Reports0],
  lists:foldl(
    fun (Report, Acc0) ->
      ArtifactRefs = openagentic_case_store_common_lookup:get_in_map(Report, [spec, artifact_refs], []),
      Acc0 ++ openagentic_case_store_common_core:ensure_list_of_maps(ArtifactRefs)
    end,
    [],
    Reports
  ).

read_objects_in_dir(Dir) ->
  [openagentic_case_store_repo_persist:read_json(Path) || Path <- json_files(Dir)].

json_files(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} ->
      [filename:join([Dir, Name]) || Name <- Names, filename:extension(Name) =:= ".json"];
    _ ->
      []
  end.

safe_list_dir(Dir) ->
  case file:list_dir(Dir) of
    {ok, Names} -> Names;
    _ -> []
  end.

load_case(RootDir, CaseId0) ->
  CaseId = openagentic_case_store_common_core:to_bin(CaseId0),
  CaseDir = openagentic_case_store_repo_paths:case_dir(RootDir, CaseId),
  Path = openagentic_case_store_repo_paths:case_file(CaseDir),
  case filelib:is_file(Path) of
    true -> {ok, openagentic_case_store_repo_persist:read_json(Path), CaseDir};
    false -> {error, not_found}
  end.
