-module(openagentic_case_store_ops).

-export([
  new_operation/4,
  mark_applied/4,
  mark_partially_applied/5,
  mark_failed/4,
  persist_operation/2
]).

new_operation(CaseId, OpType, Input0, Now) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  OperationId = openagentic_case_store_common_meta:new_id(<<"op">>),
  #{
    header => openagentic_case_store_common_meta:header(OperationId, <<"operation">>, Now),
    links => #{case_id => CaseId, related_object_refs => []},
    spec => #{op_type => OpType},
    state => #{status => <<"pending">>, applied_steps => [], failed_steps => [], retry_count => 0},
    audit =>
      openagentic_case_store_common_meta:compact_map(
        #{initiator_op_id => initiator_from_input(Input)}
      ),
    ext => #{}
  }.

mark_applied(Operation0, TargetRefs0, AppliedSteps0, Now) ->
  update_operation_state(Operation0, <<"applied">>, TargetRefs0, AppliedSteps0, [], Now).

mark_partially_applied(Operation0, TargetRefs0, AppliedSteps0, FailedSteps0, Now) ->
  update_operation_state(Operation0, <<"partially_applied">>, TargetRefs0, AppliedSteps0, FailedSteps0, Now).

mark_failed(Operation0, TargetRefs0, FailedSteps0, Now) ->
  update_operation_state(Operation0, <<"failed">>, TargetRefs0, [], FailedSteps0, Now).

persist_operation(CaseDir, Operation) ->
  openagentic_case_store_repo_persist:persist_case_object(
    CaseDir,
    openagentic_case_store_repo_paths:operation_file(CaseDir, openagentic_case_store_common_meta:id_of(Operation)),
    Operation
  ).

update_operation_state(Operation0, Status, TargetRefs0, AppliedSteps0, FailedSteps0, Now) ->
  TargetRefs = openagentic_case_store_common_core:ensure_list(TargetRefs0),
  AppliedSteps = openagentic_case_store_common_core:ensure_list(AppliedSteps0),
  FailedSteps = openagentic_case_store_common_core:ensure_list(FailedSteps0),
  openagentic_case_store_repo_persist:update_object(
    Operation0,
    Now,
    fun (Obj) ->
      Obj#{
        links => maps:merge(maps:get(links, Obj, #{}), #{related_object_refs => TargetRefs}),
        state =>
          maps:merge(
            maps:get(state, Obj, #{}),
            #{status => Status, applied_steps => AppliedSteps, failed_steps => FailedSteps}
          )
      }
    end
  ).

initiator_from_input(Input) ->
  openagentic_case_store_common_meta:first_defined(
    [
      openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
      openagentic_case_store_common_lookup:get_bin(Input, [created_by_op_id, createdByOpId], undefined),
      openagentic_case_store_common_lookup:get_bin(Input, [started_by_op_id, startedByOpId], undefined),
      openagentic_case_store_common_lookup:get_bin(Input, [inspected_by_op_id, inspectedByOpId], undefined),
      openagentic_case_store_common_lookup:get_bin(Input, [approved_by_op_id, approvedByOpId], undefined)
    ]
  ).
