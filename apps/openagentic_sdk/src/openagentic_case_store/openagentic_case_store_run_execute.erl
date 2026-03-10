-module(openagentic_case_store_run_execute).
-export([execute_run_attempt/8]).

execute_run_attempt(RootDir, CaseId, CaseDir, Task0, Version, Run0, PreviousAttemptId, Input0) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  Now = openagentic_case_store_common_meta:now_ts(),
  TaskId = openagentic_case_store_common_meta:id_of(Task0),
  RunId = openagentic_case_store_common_meta:id_of(Run0),
  AttemptId = openagentic_case_store_common_meta:new_id(<<"attempt">>),
  AttemptIndex = openagentic_case_store_common_lookup:get_number(openagentic_case_store_common_lookup:get_in_map(Run0, [state], #{}), [attempt_count], 0) + 1,
  ScratchRef = openagentic_case_store_repo_paths:attempt_scratch_ref(TaskId, RunId, AttemptId),
  ScratchDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(ScratchRef)]),
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  ExecutionSessionId = openagentic_case_store_run_attempt_session:create_attempt_session(RootDir, CaseId, TaskId, RunId, AttemptId),
  CredentialBindings = openagentic_case_store_repo_readers:read_task_credential_bindings(CaseDir, TaskId),
  CredentialSnapshot = openagentic_case_store_run_inputs:build_credential_resolution_snapshot(CredentialBindings),
  AllowedTools = openagentic_case_store_run_inputs:resolve_allowed_tools(Version),
  RunContext = openagentic_case_store_run_context:build_monitoring_run_context(CaseDir, Task0, Version),
  ExecutionProfile = openagentic_case_store_run_inputs:build_execution_profile_snapshot(Input, Task0, Version, AllowedTools, ScratchRef),
  Attempt0 =
    openagentic_case_store_run_build:build_run_attempt(
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
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_attempt_file(CaseDir, TaskId, AttemptId), Attempt0),
  Run1 =
    openagentic_case_store_repo_persist:update_object(
      Run0,
      Now,
      fun (Obj) ->
        Obj#{
          links => maps:merge(maps:get(links, Obj, #{}), #{latest_attempt_id => AttemptId}),
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"running">>, attempt_count => AttemptIndex, last_attempt_status => <<"running">>, started_at => Now}
            )
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_file(CaseDir, TaskId, RunId), Run1),
  Task1 =
    openagentic_case_store_repo_persist:update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{state => maps:merge(maps:get(state, Obj, #{}), #{latest_run_id => RunId})}
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), Task1),
  openagentic_case_store_run_attempt_session:append_attempt_start_event(RootDir, ExecutionSessionId, CaseId, TaskId, RunId, AttemptId),
  Prompt = openagentic_case_store_run_inputs:build_monitoring_prompt(Task1, Version, Attempt0, RunContext),
  RuntimeOpts = openagentic_case_store_run_runtime_opts:build_monitoring_runtime_opts(RootDir, CaseDir, Task1, ScratchDir, ExecutionSessionId, AllowedTools, Input),
  case openagentic_runtime:query(Prompt, RuntimeOpts) of
    {ok, RuntimeRes0} ->
      RuntimeRes = openagentic_case_store_common_core:ensure_map(RuntimeRes0),
      FinalText = openagentic_case_store_common_lookup:get_bin(RuntimeRes, [final_text, finalText], <<>>),
      case openagentic_case_store_run_parse_main:parse_monitoring_delivery(FinalText, TaskId, RunId, Now) of
        {ok, Delivery} ->
          case openagentic_case_store_run_contract:validate_report_contract(Version, Delivery) of
            ok ->
              openagentic_case_store_run_finalize_success:finalize_run_success(RootDir, CaseId, CaseDir, Task1, Version, Run1, Attempt0, Delivery, Input);
            {error, FailureClass, FailureSummary} ->
              openagentic_case_store_run_finalize_failure:finalize_run_failure(
                RootDir,
                CaseId,
                CaseDir,
                Task1,
                Run1,
                Attempt0,
                FailureClass,
                FailureSummary,
                FinalText,
                Input
              )
          end;
        {error, FailureClass, FailureSummary} ->
          openagentic_case_store_run_finalize_failure:finalize_run_failure(
            RootDir,
            CaseId,
            CaseDir,
            Task1,
            Run1,
            Attempt0,
            FailureClass,
            FailureSummary,
            FinalText,
            Input
          )
      end;
    {error, {runtime_error, Reason, _SessionId}} ->
      {FailureClass, FailureSummary} = openagentic_case_store_run_failure_classify:classify_runtime_failure(Reason),
      openagentic_case_store_run_finalize_failure:finalize_run_failure(
        RootDir,
        CaseId,
        CaseDir,
        Task1,
        Run1,
        Attempt0,
        FailureClass,
        FailureSummary,
        undefined,
        Input
      );
    {error, Reason} ->
      {FailureClass, FailureSummary} = openagentic_case_store_run_failure_classify:classify_runtime_failure(Reason),
      openagentic_case_store_run_finalize_failure:finalize_run_failure(
        RootDir,
        CaseId,
        CaseDir,
        Task1,
        Run1,
        Attempt0,
        FailureClass,
        FailureSummary,
        undefined,
        Input
      )
  end.
