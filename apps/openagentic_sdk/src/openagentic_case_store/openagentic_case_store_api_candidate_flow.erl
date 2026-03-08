-module(openagentic_case_store_api_candidate_flow).
-export([extract_candidates/2, discard_candidate/2, get_case_overview/2, list_templates/2]).

extract_candidates(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  {ok, CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  RoundId = openagentic_case_store_candidates_infer:resolve_round_id(CaseDir, Input, CaseObj),
  RoundObj = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:round_file(CaseDir, RoundId)),
  WorkflowSessionId = openagentic_case_store_common_lookup:get_in_map(RoundObj, [links, workflow_session_id], <<>>),
  Items0 = openagentic_case_store_common_lookup:get_list(Input, [items, candidates], []),
  CandidateSpecs =
    case openagentic_case_store_common_core:normalize_candidate_specs(Items0) of
      [] -> openagentic_case_store_candidates_infer:infer_candidate_specs_from_session(RootDir, WorkflowSessionId, openagentic_case_store_common_meta:default_timezone(CaseObj));
      Specs -> Specs
    end,
  Now = openagentic_case_store_common_meta:now_ts(),
  {Candidates, Mail} = openagentic_case_store_candidates_build:create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, CandidateSpecs, Now),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  {ok, #{case_id => CaseId, round_id => RoundId, candidates => Candidates, mail => Mail, overview => openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)}}.

discard_candidate(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  CandidateId = openagentic_case_store_common_lookup:required_bin(Input, [candidate_id, candidateId]),
  {ok, _CaseObj, CaseDir} = openagentic_case_store_repo_readers:load_case(RootDir, CaseId),
  CandidatePath = openagentic_case_store_repo_paths:candidate_file(CaseDir, CandidateId),
  Candidate0 = openagentic_case_store_repo_persist:read_json(CandidatePath),
  Now = openagentic_case_store_common_meta:now_ts(),
  Candidate1 =
    openagentic_case_store_repo_persist:update_object(
      Candidate0,
      Now,
      fun (Obj) ->
        Obj#{
          state => maps:put(status, <<"discarded">>, maps:get(state, Obj, #{})),
          audit =>
            maps:merge(
              maps:get(audit, Obj, #{}),
              openagentic_case_store_common_meta:compact_map(
                #{
                  discarded_at => Now,
                  discarded_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                  discard_reason => openagentic_case_store_common_lookup:get_bin(Input, [reason], undefined)
                }
              )
            )
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, CandidatePath, Candidate1),
  ok = openagentic_case_store_mail:mark_candidate_mail_acted(CaseDir, CandidateId, <<"discard">>, openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined), Now),
  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  {ok, Candidate1}.

get_case_overview(RootDir0, CaseId0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  CaseId = openagentic_case_store_common_core:to_bin(CaseId0),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {ok, _CaseObj, _CaseDir} -> {ok, openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)};
    {error, Reason} -> {error, Reason}
  end.

list_templates(RootDir0, CaseIdOrInput) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  CaseId =
    case CaseIdOrInput of
      Map when is_map(Map) -> openagentic_case_store_common_lookup:required_bin(Map, [case_id, caseId]);
      Value -> openagentic_case_store_common_core:to_bin(Value)
    end,
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {ok, _CaseObj, CaseDir} ->
      {ok, openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_template_objects(filename:join([CaseDir, "meta", "templates"])))};
    {error, Reason} -> {error, Reason}
  end.
