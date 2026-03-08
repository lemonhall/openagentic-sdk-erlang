-module(openagentic_case_store_api_case_create).
-export([create_case_from_round/2]).

create_case_from_round(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  WorkflowSessionId = openagentic_case_store_common_lookup:required_bin(Input, [workflow_session_id, workflowSessionId]),
  try
    _ = openagentic_session_store:session_dir(RootDir, openagentic_case_store_common_core:ensure_list(WorkflowSessionId)),
    ok = openagentic_case_store_case_support:ensure_workflow_session_completed(RootDir, WorkflowSessionId),
    Now = openagentic_case_store_common_meta:now_ts(),
    CaseId = openagentic_case_store_common_meta:new_id(<<"case">>),
    RoundId = openagentic_case_store_common_meta:new_id(<<"round">>),
    CaseDir = openagentic_case_store_repo_paths:case_dir(RootDir, CaseId),
    ok = openagentic_case_store_repo_paths:ensure_case_layout(CaseDir),
    CaseObj =
      #{
        header => openagentic_case_store_common_meta:header(CaseId, <<"case">>, Now),
        links =>
          openagentic_case_store_common_meta:compact_map(
            #{
              origin_round_id => RoundId,
              origin_workflow_session_id => WorkflowSessionId,
              current_round_id => RoundId,
              latest_briefing_id => undefined,
              active_pack_ids => []
            }
          ),
        spec =>
          openagentic_case_store_common_meta:compact_map(
            #{
              title => openagentic_case_store_common_lookup:get_bin(Input, [title], <<"Untitled Case">>),
              display_code => openagentic_case_store_common_lookup:get_bin(Input, [display_code, displayCode], openagentic_case_store_common_meta:display_code(<<"CASE">>)),
              topic => openagentic_case_store_common_lookup:get_bin(Input, [topic], undefined),
              owner => openagentic_case_store_common_lookup:get_bin(Input, [owner], undefined),
              default_timezone => openagentic_case_store_common_lookup:get_bin(Input, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>),
              labels => openagentic_case_store_common_lookup:get_list(Input, [labels], []),
              opening_brief => openagentic_case_store_common_lookup:get_bin(Input, [opening_brief, openingBrief], <<>>)
            }
          ),
        state =>
          #{
            status => <<"active">>,
            phase => <<"post_deliberation_extraction">>,
            current_summary => openagentic_case_store_common_lookup:get_bin(Input, [current_summary, currentSummary], <<>>),
            active_task_count => 0,
            active_pack_count => 0
          },
        audit =>
          openagentic_case_store_common_meta:compact_map(
            #{
              created_from => <<"workflow_session">>,
              created_from_session_id => WorkflowSessionId,
              created_by => openagentic_case_store_common_lookup:get_bin(Input, [created_by, createdBy], undefined)
            }
          ),
        ext => #{}
      },
    RoundObj =
      #{
        header => openagentic_case_store_common_meta:header(RoundId, <<"deliberation_round">>, Now),
        links =>
          openagentic_case_store_common_meta:compact_map(
            #{
              case_id => CaseId,
              parent_round_id => openagentic_case_store_common_lookup:get_bin(Input, [parent_round_id, parentRoundId], undefined),
              workflow_session_id => WorkflowSessionId,
              triggering_briefing_id => openagentic_case_store_common_lookup:get_bin(Input, [triggering_briefing_id, triggeringBriefingId], undefined),
              resolution_id => openagentic_case_store_common_lookup:get_bin(Input, [resolution_id, resolutionId], undefined)
            }
          ),
        spec =>
          openagentic_case_store_common_meta:compact_map(
            #{
              round_index => openagentic_case_store_common_lookup:get_int(Input, [round_index, roundIndex], 1),
              kind => openagentic_case_store_common_lookup:get_bin(Input, [kind], <<"initial_deliberation">>),
              trigger_reason => openagentic_case_store_common_lookup:get_bin(Input, [trigger_reason, triggerReason], <<"workflow_session_promoted_to_case">>),
              starter_role => openagentic_case_store_common_lookup:get_bin(Input, [starter_role, starterRole], <<"court">>),
              input_material_refs => openagentic_case_store_common_lookup:get_list(Input, [input_material_refs, inputMaterialRefs], [])
            }
          ),
        state =>
          openagentic_case_store_common_meta:compact_map(
            #{
              status => openagentic_case_store_common_lookup:get_bin(Input, [round_status, roundStatus], <<"completed">>),
              phase => openagentic_case_store_common_lookup:get_bin(Input, [round_phase, roundPhase], <<"concluded">>),
              started_at => openagentic_case_store_common_lookup:get_number(Input, [started_at, startedAt], undefined),
              ended_at => Now
            }
          ),
        audit => openagentic_case_store_common_meta:compact_map(#{created_from_session_id => WorkflowSessionId}),
        ext => #{}
      },
    ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:case_file(CaseDir), CaseObj),
    ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:round_file(CaseDir, RoundId), RoundObj),
    ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
    BaseRes = #{'case' => CaseObj, round => RoundObj},
    case openagentic_case_store_common_lookup:get_bool(Input, [auto_extract, autoExtract], true) of
      true ->
        case openagentic_case_store_api_candidate_flow:extract_candidates(RootDir, #{case_id => CaseId, round_id => RoundId}) of
          {ok, Extracted} ->
            {ok,
             maps:merge(
               BaseRes,
               #{
                 candidates => maps:get(candidates, Extracted, []),
                 mail => maps:get(mail, Extracted, []),
                 overview => maps:get(overview, Extracted, undefined)
               }
             )};
          {error, ExtractReason} -> {error, ExtractReason}
        end;
      false ->
        {ok, BaseRes}
    end
  catch
    error:{missing_required_field, Field} -> {error, {missing_required_field, Field}};
    error:{invalid_session_id, _} -> {error, invalid_workflow_session_id};
    throw:{error, Reason} -> {error, Reason}
  end.
