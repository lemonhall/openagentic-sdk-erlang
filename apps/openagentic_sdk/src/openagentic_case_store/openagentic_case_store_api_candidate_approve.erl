-module(openagentic_case_store_api_candidate_approve).
-export([approve_candidate/2]).

approve_candidate(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  CandidateId = openagentic_case_store_common_lookup:required_bin(Input, [candidate_id, candidateId]),
  {ok, _CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  CandidatePath = openagentic_case_store_repo_paths:candidate_file(CaseDir, CandidateId),
  Candidate0 = openagentic_case_store_repo_persist:read_json(CandidatePath),
  case approval_error(Candidate0) of
    undefined -> approve_candidate_ready(RootDir, Input, CaseId, CaseDir, CandidateId, CandidatePath, Candidate0);
    Error -> {error, Error}
  end.

approval_error(Candidate0) ->
  case openagentic_case_store_common_lookup:get_in_map(Candidate0, [state, status], <<>>) of
    <<"approved">> -> already_approved;
    <<"discarded">> -> candidate_discarded;
    _ -> undefined
  end.

approve_candidate_ready(RootDir, Input, CaseId, CaseDir, CandidateId, CandidatePath, Candidate0) ->
  Context = openagentic_case_store_candidate_approve_build:build_context(CaseDir, Candidate0, Input),
  TaskId = maps:get(task_id, Context),
  VersionId = maps:get(version_id, Context),
  WorkspaceRef = maps:get(workspace_ref, Context),
  TaskWorkspaceDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(WorkspaceRef)]),
  ok = filelib:ensure_dir(filename:join([TaskWorkspaceDir, "x"])),
  ok = openagentic_case_store_case_support:seed_task_workspace(TaskWorkspaceDir, Candidate0, Input),
  TaskObj = openagentic_case_store_candidate_approve_build:build_task(CaseId, CandidateId, Candidate0, Input, Context),
  TaskVersionObj = openagentic_case_store_candidate_approve_build:build_version(CaseId, Candidate0, Input, Context),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), TaskObj),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_version_file(CaseDir, TaskId, VersionId), TaskVersionObj),
  Candidate1 = approved_candidate(Candidate0, TaskId, Input, maps:get(now, Context)),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, CandidatePath, Candidate1),
  ok = openagentic_case_store_mail:mark_candidate_mail_acted(CaseDir, CandidateId, <<"approve">>, openagentic_case_store_common_lookup:get_bin(Input, [approved_by_op_id, approvedByOpId], undefined), maps:get(now, Context)),
  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  {ok, #{candidate => Candidate1, task => TaskObj, task_version => TaskVersionObj, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}.

approved_candidate(Candidate0, TaskId, Input, Now) ->
  openagentic_case_store_repo_persist:update_object(
    Candidate0,
    Now,
    fun (Obj) ->
      Obj#{
        links => maps:put(approved_task_id, TaskId, maps:get(links, Obj, #{})),
        state => maps:put(status, <<"approved">>, maps:get(state, Obj, #{})),
        audit =>
          maps:merge(
            maps:get(audit, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(
              #{
                approved_at => Now,
                approved_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [approved_by_op_id, approvedByOpId], undefined),
                approval_summary => openagentic_case_store_common_lookup:get_bin(Input, [approval_summary, approvalSummary], undefined)
              }
            )
          )
      }
    end
  ).
