-module(openagentic_case_store_run_finalize_failure).
-export([finalize_run_failure/10, maybe_write_failure_output/3, write_attempt_delivery_files/2]).

finalize_run_failure(RootDir, CaseId, CaseDir, Task0, Run0, Attempt0, FailureClass, FailureSummary0, RawOutput, Input0) ->
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  Now = openagentic_case_store_common_meta:now_ts(),
  TaskId = openagentic_case_store_common_meta:id_of(Task0),
  RunId = openagentic_case_store_common_meta:id_of(Run0),
  AttemptId = openagentic_case_store_common_meta:id_of(Attempt0),
  ScratchDir = filename:join([CaseDir, openagentic_case_store_common_core:ensure_list(openagentic_case_store_common_lookup:get_in_map(Attempt0, [links, scratch_ref], <<>>))]),
  FailureSummary = openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(FailureSummary0)),
  ok = maybe_write_failure_output(ScratchDir, RawOutput, FailureSummary),
  Attempt1 =
    openagentic_case_store_repo_persist:update_object(
      Attempt0,
      Now,
      fun (Obj) ->
        Obj#{
          state =>
            maps:merge(
              maps:get(state, Obj, #{}),
              #{status => <<"failed">>, ended_at => Now, failure_class => FailureClass, failure_summary => FailureSummary, promoted_artifact_refs => []}
            )
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_attempt_file(CaseDir, TaskId, AttemptId), Attempt1),
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
              #{status => <<"failed">>, attempt_count => openagentic_case_store_common_lookup:get_in_map(Attempt1, [spec, attempt_index], 1), last_attempt_status => <<"failed">>, completed_at => Now, result_summary => FailureSummary}
            ),
          audit => maps:merge(maps:get(audit, Obj, #{}), #{failure_class => FailureClass, failure_summary => FailureSummary})
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:run_file(CaseDir, TaskId, RunId), Run1),
  ExceptionBrief = openagentic_case_store_run_failure_mail:build_exception_brief(CaseId, Task0, Run1, Attempt1, FailureClass, FailureSummary, Now),
  FailureMail = openagentic_case_store_run_failure_mail:build_task_run_failure_mail(CaseId, Task0, Run1, Attempt1, ExceptionBrief, FailureClass, FailureSummary, Now),
  {TaskStatus, TaskHealth, RectificationMail} = openagentic_case_store_run_failure_classify:derive_task_failure_outcome(CaseDir, Task0, Now),
  Task1 =
    openagentic_case_store_repo_persist:update_object(
      Task0,
      Now,
      fun (Obj) ->
        Obj#{
          state => maps:merge(maps:get(state, Obj, #{}), #{status => TaskStatus, health => TaskHealth, latest_run_id => RunId})
        }
      end
    ),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:task_file(CaseDir, TaskId), Task1),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:exception_brief_file(CaseDir, TaskId, openagentic_case_store_common_meta:id_of(ExceptionBrief)), ExceptionBrief),
  ok = openagentic_case_store_run_failure_mail:maybe_persist_mail(CaseDir, FailureMail),
  ok = openagentic_case_store_run_failure_mail:maybe_persist_mail(CaseDir, RectificationMail),
  ok = openagentic_case_store_case_state:refresh_case_state(RootDir, CaseId),
  ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
  Base =
    #{
      task => Task1,
      run => Run1,
      run_attempt => Attempt1,
      exception_brief => ExceptionBrief,
      mail => FailureMail,
      overview => maybe_response_overview(RootDir, CaseId, Input)
    },
  case RectificationMail of
    undefined -> {ok, Base};
    _ -> {ok, Base#{rectification_mail => RectificationMail}}
  end.

maybe_write_failure_output(ScratchDir, RawOutput, FailureSummary) ->
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  case RawOutput of
    undefined -> file:write_file(filename:join([ScratchDir, "failure.txt"]), <<FailureSummary/binary, "\n">>);
    <<>> -> file:write_file(filename:join([ScratchDir, "failure.txt"]), <<FailureSummary/binary, "\n">>);
    Bin -> file:write_file(filename:join([ScratchDir, "raw-output.txt"]), <<(openagentic_case_store_common_core:to_bin(Bin))/binary, "\n">>)
  end,
  ok.

write_attempt_delivery_files(ScratchDir, Delivery) ->
  ok = filelib:ensure_dir(filename:join([ScratchDir, "x"])),
  ok = file:write_file(filename:join([ScratchDir, "report.md"]), <<(openagentic_case_store_common_lookup:get_bin(Delivery, [report_markdown], <<>>))/binary, "\n">>),
  FactsBody = openagentic_json:encode_safe(#{facts => maps:get(facts, Delivery, [])}),
  ArtifactsBody = openagentic_json:encode_safe(#{artifacts => maps:get(artifacts, Delivery, [])}),
  ok = file:write_file(filename:join([ScratchDir, "facts.json"]), <<FactsBody/binary, "\n">>),
  ok = file:write_file(filename:join([ScratchDir, "artifacts.json"]), <<ArtifactsBody/binary, "\n">>).

maybe_response_overview(RootDir, CaseId, Input) ->
  case maps:get(include_overview, Input, true) of
    false -> undefined;
    _ -> openagentic_case_store_case_state:get_case_overview_map(RootDir, CaseId)
  end.
