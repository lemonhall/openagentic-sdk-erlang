-module(openagentic_case_store_task_revise_build).
-export([build_revised_task_version/7, append_governance_revision_event/7]).

build_revised_task_version(CaseId, TaskId, VersionId, CurrentVersion0, Input, GovernanceSessionId, Now) ->
  CurrentVersion = openagentic_case_store_common_core:ensure_map(CurrentVersion0),
  CurrentLinks = openagentic_case_store_common_core:ensure_map(maps:get(links, CurrentVersion, #{})),
  CurrentSpec = openagentic_case_store_common_core:ensure_map(maps:get(spec, CurrentVersion, #{})),
  #{
    header => openagentic_case_store_common_meta:header(VersionId, <<"task_version">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          previous_version_id => openagentic_case_store_common_meta:id_of(CurrentVersion),
          derived_from_template_ref =>
            openagentic_case_store_common_lookup:get_bin(Input, [derived_from_template_ref, derivedFromTemplateRef], openagentic_case_store_common_lookup:get_in_map(CurrentLinks, [derived_from_template_ref], undefined)),
          approved_by_op_id =>
            openagentic_case_store_common_lookup:get_bin(
              Input,
              [approved_by_op_id, approvedByOpId],
              openagentic_case_store_common_lookup:get_bin(Input, [revised_by_op_id, revisedByOpId], openagentic_case_store_common_lookup:get_in_map(CurrentLinks, [approved_by_op_id], undefined))
            )
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          objective => openagentic_case_store_common_lookup:get_bin(Input, [objective], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [objective], <<>>)),
          schedule_policy => openagentic_case_store_common_lookup:choose_map(Input, [schedule_policy, schedulePolicy], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [schedule_policy], #{})),
          report_contract => openagentic_case_store_common_lookup:choose_map(Input, [report_contract, reportContract], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [report_contract], #{})),
          alert_rules => openagentic_case_store_common_lookup:choose_map(Input, [alert_rules, alertRules], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [alert_rules], #{})),
          source_strategy => openagentic_case_store_common_lookup:choose_map(Input, [source_strategy, sourceStrategy], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [source_strategy], #{})),
          tool_profile => openagentic_case_store_common_lookup:choose_map(Input, [tool_profile, toolProfile], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [tool_profile], #{})),
          credential_requirements =>
            openagentic_case_store_common_lookup:choose_map(Input, [credential_requirements, credentialRequirements], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [credential_requirements], #{})),
          autonomy_policy => openagentic_case_store_common_lookup:choose_map(Input, [autonomy_policy, autonomyPolicy], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [autonomy_policy], #{})),
          promotion_policy => openagentic_case_store_common_lookup:choose_map(Input, [promotion_policy, promotionPolicy], openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [promotion_policy], #{}))
        }
      ),
    state => #{status => <<"active">>, activated_at => Now, superseded_at => undefined},
    audit =>
      openagentic_case_store_common_meta:compact_map(
        #{
          change_summary => openagentic_case_store_common_lookup:get_bin(Input, [change_summary, changeSummary], <<"revise task version">>),
          approval_summary => openagentic_case_store_common_lookup:get_bin(Input, [approval_summary, approvalSummary], undefined),
          revised_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
          governance_session_id => GovernanceSessionId
        }
      ),
    ext => #{}
  }.

append_governance_revision_event(RootDir, GovernanceSessionId, CaseId, TaskId, PreviousVersionId, VersionId, Input) ->
  Event =
    openagentic_case_store_common_meta:compact_map(
      #{
        type => <<"governance.task_version.created">>,
        case_id => CaseId,
        task_id => TaskId,
        governance_session_id => GovernanceSessionId,
        previous_version_id => PreviousVersionId,
        task_version_id => VersionId,
        revised_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [revised_by_op_id, revisedByOpId], undefined),
        change_summary => openagentic_case_store_common_lookup:get_bin(Input, [change_summary, changeSummary], undefined),
        objective => openagentic_case_store_common_lookup:get_bin(Input, [objective], undefined)
      }
    ),
  case catch openagentic_session_store:append_event(RootDir, openagentic_case_store_common_core:ensure_list(GovernanceSessionId), Event) of
    {ok, _} -> ok;
    _ -> ok
  end.
