-module(openagentic_case_store_run_build).
-export([build_monitoring_run/7, build_run_attempt/12, default_attempt_reason/1, task_timezone/1]).

build_monitoring_run(CaseId, TaskId, VersionId, RunId, Version, Input, Now) ->
  #{
    header => openagentic_case_store_common_meta:header(RunId, <<"monitoring_run">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          task_version_id => VersionId,
          pack_ids => [],
          latest_attempt_id => undefined,
          successful_attempt_id => undefined,
          report_id => undefined
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          run_kind => openagentic_case_store_common_lookup:get_bin(Input, [run_kind, runKind], <<"manual">>),
          trigger_type => openagentic_case_store_common_lookup:get_bin(Input, [trigger_type, triggerType], <<"manual">>),
          trigger_ref => openagentic_case_store_common_lookup:get_bin(Input, [trigger_ref, triggerRef], undefined),
          expected_outputs_contract_ref => <<VersionId/binary, "#report_contract">>,
          planned_for_at => openagentic_case_store_common_lookup:get_number(Input, [planned_for_at, plannedForAt], Now),
          timezone => task_timezone(Version)
        }
      ),
    state =>
      #{
        status => <<"scheduled">>,
        attempt_count => 0,
        last_attempt_status => undefined,
        completed_at => undefined,
        result_summary => undefined,
        started_at => undefined
      },
    audit => openagentic_case_store_common_meta:compact_map(#{triggered_at => Now, triggered_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined)}),
    ext => #{}
  }.

build_run_attempt(
  CaseId,
  TaskId,
  RunId,
  AttemptId,
  PreviousAttemptId,
  ExecutionSessionId,
  ScratchRef,
  AttemptIndex,
  Input,
  ExecutionProfile,
  CredentialSnapshot,
  Now
) ->
  #{
    header => openagentic_case_store_common_meta:header(AttemptId, <<"run_attempt">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          task_id => TaskId,
          run_id => RunId,
          previous_attempt_id => PreviousAttemptId,
          execution_session_id => ExecutionSessionId,
          scratch_ref => ScratchRef
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          attempt_index => AttemptIndex,
          attempt_reason => openagentic_case_store_common_lookup:get_bin(Input, [attempt_reason, attemptReason], default_attempt_reason(AttemptIndex)),
          execution_profile_snapshot => ExecutionProfile,
          strategy_note => openagentic_case_store_common_lookup:get_bin(Input, [strategy_note, strategyNote], undefined),
          credential_resolution_snapshot => CredentialSnapshot
        }
      ),
    state =>
      #{
        status => <<"running">>,
        started_at => Now,
        ended_at => undefined,
        failure_class => undefined,
        failure_summary => undefined,
        promoted_artifact_refs => []
      },
    audit => openagentic_case_store_common_meta:compact_map(#{triggered_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined)}),
    ext => #{}
  }.

default_attempt_reason(1) -> <<"initial_execution">>;
default_attempt_reason(_) -> <<"retry_after_failure">>.

task_timezone(Version) ->
  SchedulePolicy = openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Version, [spec, schedule_policy], #{})),
  openagentic_case_store_common_lookup:get_bin(SchedulePolicy, [timezone], <<"Asia/Shanghai">>).
