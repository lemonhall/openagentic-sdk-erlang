-module(openagentic_case_store_case_state).
-export([get_case_overview_map/2, refresh_case_state/2, counts_as_live_task/1, rebuild_indexes/2, group_ids_by_status/1]).

get_case_overview_map(RootDir, CaseId) ->
  {ok, CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Rounds = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  Candidates = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"]))),
  Tasks = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"]))),
  Mail = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "mail"]))),
  Templates = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_template_objects(filename:join([CaseDir, "meta", "templates"]))),
  #{'case' => CaseObj, rounds => Rounds, candidates => Candidates, tasks => Tasks, templates => Templates, mail => Mail}.

refresh_case_state(RootDir, CaseId) ->
  {ok, CaseObj0, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Tasks = openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  ActiveTaskCount =
    length(
      [
        T
       || T <- Tasks,
          counts_as_live_task(openagentic_case_store_common_lookup:get_in_map(T, [state, status], <<>>))
      ]
    ),
  Phase =
    case ActiveTaskCount > 0 of
      true -> <<"monitoring_active">>;
      false -> <<"post_deliberation_extraction">>
  end,
  CaseObj1 =
    openagentic_case_store_repo_persist:update_object(
      CaseObj0,
      openagentic_case_store_common_meta:now_ts(),
      fun (Obj) ->
        State0 = maps:get(state, Obj, #{}),
        Obj#{state => State0#{active_task_count => ActiveTaskCount, phase => Phase}}
      end
    ),
  openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:case_file(CaseDir), CaseObj1).

counts_as_live_task(<<"active">>) -> true;
counts_as_live_task(<<"rectification_required">>) -> true;
counts_as_live_task(_) -> false.

rebuild_indexes(RootDir, CaseId) ->
  {ok, _CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  Candidates = openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "candidates"])),
  Tasks = openagentic_case_store_repo_readers:read_task_objects(filename:join([CaseDir, "meta", "tasks"])),
  Mail = openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "mail"])),
  IndexDir = filename:join([CaseDir, "meta", "indexes"]),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "candidates-by-status.json"]), group_ids_by_status(Candidates)),
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "tasks-by-status.json"]), group_ids_by_status(Tasks)),
  UnreadMail = [openagentic_case_store_common_meta:id_of(M) || M <- Mail, openagentic_case_store_common_lookup:get_in_map(M, [state, status], <<>>) =:= <<"unread">>],
  ok = openagentic_case_store_repo_persist:write_json(filename:join([IndexDir, "mail-unread.json"]), #{mail_ids => UnreadMail}),
  ok.

group_ids_by_status(Objs) ->
  lists:foldl(
    fun (Obj, Acc0) ->
      Status = openagentic_case_store_common_lookup:get_in_map(Obj, [state, status], <<"unknown">>),
      Id = openagentic_case_store_common_meta:id_of(Obj),
      Prev = maps:get(Status, Acc0, []),
      Acc0#{Status => Prev ++ [Id]}
    end,
    #{},
    Objs
  ).
