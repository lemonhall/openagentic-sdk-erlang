-module(openagentic_case_store_repo_readers).
-export([sort_by_created_at/1, read_task_objects/1, read_task_objects_indexed/1, read_template_objects/1, read_task_versions/2, read_task_credential_bindings/2, read_task_runs/2, read_task_run_attempts/2, read_task_fact_reports/2, read_task_exception_briefs/2, read_mail_objects_indexed/2, read_observation_packs/1, read_observation_packs_indexed/1, read_inspection_reviews/1, read_inspection_reviews_indexed/1, read_reconsideration_packages/1, read_reconsideration_packages_indexed/1, build_task_artifacts/1, read_objects_in_dir/1, json_files/1, safe_list_dir/1, load_case/2]).

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

read_observation_packs(CaseDir) ->
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "packs"]))).

read_inspection_reviews(CaseDir) ->
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "inspection_reviews"]))).

read_reconsideration_packages(CaseDir) ->
  sort_by_created_at(read_objects_in_dir(filename:join([CaseDir, "meta", "reconsideration_packages"]))).

read_task_objects_indexed(CaseDir) ->
  read_all_status_indexed_objects(
    filename:join([CaseDir, "meta", "indexes", "tasks-by-status.json"]),
    fun (TaskId) -> openagentic_case_store_repo_paths:task_file(CaseDir, TaskId) end,
    fun () -> read_task_objects(filename:join([CaseDir, "meta", "tasks"])) end
  ).

read_mail_objects_indexed(CaseDir, StatusFilter0) ->
  StatusFilter = normalize_status_filter(StatusFilter0),
  MailRoot = filename:join([CaseDir, "meta", "mail"]),
  MailPathFun = fun (MailId) -> openagentic_case_store_repo_paths:mail_file(CaseDir, MailId) end,
  ReadAllFallback = fun () -> sort_by_created_at(read_objects_in_dir(MailRoot)) end,
  ReadFilteredFallback =
    fun (Status) ->
      sort_by_created_at(
        [
          MailObj
         || MailObj <- read_objects_in_dir(MailRoot),
            openagentic_case_store_common_lookup:get_in_map(MailObj, [state, status], <<>>) =:= Status
        ]
      )
    end,
  case StatusFilter of
    undefined ->
      read_all_status_indexed_objects(filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"]), MailPathFun, ReadAllFallback);
    <<"all">> ->
      read_all_status_indexed_objects(filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"]), MailPathFun, ReadAllFallback);
    <<"unread">> ->
      case maybe_read_mail_unread_ids(filename:join([CaseDir, "meta", "indexes", "mail-unread.json"])) of
        {ok, MailIds} -> sort_by_created_at(read_objects_by_ids(MailIds, MailPathFun));
        error ->
          read_status_indexed_objects(
            filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"]),
            <<"unread">>,
            MailPathFun,
            fun () -> ReadFilteredFallback(<<"unread">>) end
          )
      end;
    Status ->
      read_status_indexed_objects(
        filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"]),
        Status,
        MailPathFun,
        fun () -> ReadFilteredFallback(Status) end
      )
  end.

read_observation_packs_indexed(CaseDir) ->
  read_all_status_indexed_objects(
    filename:join([CaseDir, "meta", "indexes", "packs-by-status.json"]),
    fun (PackId) -> openagentic_case_store_repo_paths:observation_pack_file(CaseDir, PackId) end,
    fun () -> read_observation_packs(CaseDir) end
  ).

read_inspection_reviews_indexed(CaseDir) ->
  read_all_status_indexed_objects(
    filename:join([CaseDir, "meta", "indexes", "inspection-reviews-by-status.json"]),
    fun (ReviewId) -> openagentic_case_store_repo_paths:inspection_review_file(CaseDir, ReviewId) end,
    fun () -> read_inspection_reviews(CaseDir) end
  ).

read_reconsideration_packages_indexed(CaseDir) ->
  read_all_status_indexed_objects(
    filename:join([CaseDir, "meta", "indexes", "reconsideration-packages-by-status.json"]),
    fun (PackageId) -> openagentic_case_store_repo_paths:reconsideration_package_file(CaseDir, PackageId) end,
    fun () -> read_reconsideration_packages(CaseDir) end
  ).

read_all_status_indexed_objects(IndexPath, PathFun, FallbackFun) ->
  case maybe_read_status_index(IndexPath) of
    {ok, IndexMap} -> sort_by_created_at(read_objects_by_ids(all_index_ids(IndexMap), PathFun));
    error -> FallbackFun()
  end.

read_status_indexed_objects(IndexPath, Status, PathFun, FallbackFun) ->
  case maybe_read_status_index(IndexPath) of
    {ok, IndexMap} -> sort_by_created_at(read_objects_by_ids(index_ids_for_status(IndexMap, Status), PathFun));
    error -> FallbackFun()
  end.

read_objects_by_ids(Ids0, PathFun) ->
  Ids = normalize_ids(Ids0),
  lists:foldl(
    fun (Id, Acc) ->
      Path = PathFun(Id),
      case filelib:is_file(Path) of
        true -> [openagentic_case_store_repo_persist:read_json(Path) | Acc];
        false -> Acc
      end
    end,
    [],
    Ids
  ).

maybe_read_status_index(Path) ->
  case maybe_read_json(Path) of
    {ok, Map0} when is_map(Map0) -> {ok, Map0};
    _ -> error
  end.

maybe_read_mail_unread_ids(Path) ->
  case maybe_read_json(Path) of
    {ok, Map0} when is_map(Map0) ->
      {ok, normalize_ids(openagentic_case_store_common_lookup:get_in_map(Map0, [mail_ids], []))};
    _ ->
      error
  end.

maybe_read_json(Path) ->
  case filelib:is_file(Path) of
    false -> error;
    true ->
      try openagentic_case_store_repo_persist:read_json(Path) of
        Json -> {ok, Json}
      catch
        _:_ -> error
      end
  end.

all_index_ids(IndexMap0) ->
  IndexMap = openagentic_case_store_common_core:ensure_map(IndexMap0),
  openagentic_case_store_common_core:unique_binaries(
    lists:flatmap(
      fun ({_Status, Ids0}) -> normalize_ids(Ids0) end,
      maps:to_list(IndexMap)
    )
  ).

index_ids_for_status(IndexMap, Status) ->
  normalize_ids(openagentic_case_store_common_lookup:get_in_map(IndexMap, [Status], [])).

normalize_ids(Ids0) when is_list(Ids0) ->
  openagentic_case_store_common_core:unique_binaries(
    [
      openagentic_case_store_common_core:to_bin(Id)
     || Id <- Ids0,
        Id =/= undefined,
        Id =/= null,
        openagentic_case_store_common_core:to_bin(Id) =/= <<>>
    ]
  );
normalize_ids(undefined) -> [];
normalize_ids(null) -> [];
normalize_ids(Id) -> normalize_ids([Id]).

normalize_status_filter(undefined) -> undefined;
normalize_status_filter(null) -> undefined;
normalize_status_filter(Status) -> openagentic_case_store_common_core:to_bin(Status).

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
