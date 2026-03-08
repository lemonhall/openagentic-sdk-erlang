-module(openagentic_case_store_run_inputs).
-export([build_execution_profile_snapshot/5, build_credential_resolution_snapshot/1, resolve_allowed_tools/1, build_monitoring_prompt/4, normalize_observed_window/3, infer_fact_time/3, has_traceable_source/1, parse_json_object/1, strip_json_code_fences/1]).

build_execution_profile_snapshot(Input, Task, Version, AllowedTools, ScratchRef) ->
  RuntimeOpts = openagentic_case_store_run_runtime_opts:normalize_runtime_opts(openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Input, [runtime_opts], openagentic_case_store_common_lookup:get_in_map(Input, [runtimeOpts], #{})))),
  ToolProfile = openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Version, [spec, tool_profile], #{})),
  openagentic_case_store_common_meta:compact_map(
    #{
      provider_mod => openagentic_case_store_common_core:to_bin(openagentic_case_store_common_lookup:find_any(RuntimeOpts, [provider_mod, providerMod])),
      model => openagentic_case_store_common_lookup:find_any(RuntimeOpts, [model]),
      base_url => openagentic_case_store_common_lookup:find_any(RuntimeOpts, [base_url, baseUrl]),
      allowed_tools => AllowedTools,
      tool_profile => ToolProfile,
      schedule_policy => openagentic_case_store_common_lookup:get_in_map(Version, [spec, schedule_policy], #{}),
      permission_mode => maps:get(mode, openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:find_any(RuntimeOpts, [permission_gate, permissionGate])), undefined),
      max_steps => openagentic_case_store_common_lookup:find_any(RuntimeOpts, [max_steps, maxSteps]),
      task_workspace_ref => openagentic_case_store_common_lookup:get_in_map(Task, [links, workspace_ref], undefined),
      scratch_ref => ScratchRef
    }
  ).

build_credential_resolution_snapshot(CredentialBindings0) ->
  CredentialBindings = [openagentic_case_store_common_core:ensure_map(B) || B <- CredentialBindings0],
  Resolved =
    [
      openagentic_case_store_common_meta:compact_map(
        #{
          credential_binding_id => openagentic_case_store_common_meta:id_of(Binding),
          slot_name => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, slot_name], undefined),
          provider => openagentic_case_store_common_lookup:get_in_map(Binding, [spec, provider], undefined),
          status => openagentic_case_store_common_lookup:get_in_map(Binding, [state, status], undefined)
        }
      )
     || Binding <- CredentialBindings
    ],
  #{used_binding_ids => [openagentic_case_store_common_meta:id_of(Binding) || Binding <- CredentialBindings, openagentic_case_store_task_auth_validation:binding_status_valid(Binding)], bindings => Resolved, fallback_used => false}.

resolve_allowed_tools(Version) ->
  ToolProfile = openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Version, [spec, tool_profile], #{})),
  case openagentic_case_store_common_lookup:find_any(ToolProfile, [allowed_tools, allowedTools]) of
    undefined -> undefined;
    Value when is_list(Value) -> [openagentic_case_store_common_core:to_bin(Item) || Item <- Value, openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(Item)) =/= <<>>];
    Value -> [openagentic_case_store_common_core:to_bin(Value)]
  end.

build_monitoring_prompt(Task, Version, Attempt, RunContext0) ->
  RunContext = openagentic_case_store_common_core:ensure_map(RunContext0),
  TaskPayload =
    #{
      task_id => openagentic_case_store_common_meta:id_of(Task),
      title => openagentic_case_store_common_lookup:get_in_map(Task, [spec, title], <<>>),
      mission_statement => openagentic_case_store_common_lookup:get_in_map(Task, [spec, mission_statement], <<>>),
      task_version_id => openagentic_case_store_common_meta:id_of(Version),
      objective => openagentic_case_store_common_lookup:get_in_map(Version, [spec, objective], <<>>),
      schedule_policy => openagentic_case_store_common_lookup:get_in_map(Version, [spec, schedule_policy], #{}),
      report_contract => openagentic_case_store_common_lookup:get_in_map(Version, [spec, report_contract], #{}),
      attempt_id => openagentic_case_store_common_meta:id_of(Attempt),
      attempt_index => openagentic_case_store_common_lookup:get_in_map(Attempt, [spec, attempt_index], 1),
      task_workspace_ref => openagentic_case_store_common_lookup:get_in_map(Task, [links, workspace_ref], <<>>),
      scratch_ref => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, scratch_ref], <<>>),
      credential_resolution_snapshot => openagentic_case_store_common_lookup:get_in_map(Attempt, [spec, credential_resolution_snapshot], #{}),
      run_context => RunContext
    },
  Payload = openagentic_json:encode_safe(TaskPayload),
  iolist_to_binary(
    [
      <<"You are the monitoring officer for one monitoring task. Execute one unattended monitoring run and return exactly one JSON object, with no prose outside JSON.\n\n">>,
      <<"Required top-level fields: report_markdown (string), facts (array), artifacts (array). Optional: result_summary, alert_summary, report_kind, observed_window.\n">>,
      <<"facts[] should include: title, fact_type, source or source_url, collection_method, value_summary, change_summary, alert_level, confidence_note, evidence_refs.\n">>,
      <<"At least one fact must contain a traceable source reference via source_url or evidence_refs.\n">>,
      <<"Task context JSON:\n">>,
      Payload,
      <<"\n">>
    ]
  ).

normalize_observed_window(Window0, Facts, Now) ->
  Window = openagentic_case_store_common_core:ensure_map(Window0),
  StartedAt =
    case openagentic_case_store_common_lookup:get_number(Window, [started_at, startedAt], undefined) of
      undefined -> infer_fact_time(Facts, observed_at, Now);
      StartedValue -> StartedValue
    end,
  EndedAt =
    case openagentic_case_store_common_lookup:get_number(Window, [ended_at, endedAt], undefined) of
      undefined -> infer_fact_time(Facts, collected_at, Now);
      EndedValue -> EndedValue
    end,
  #{started_at => StartedAt, ended_at => EndedAt}.

infer_fact_time([], _Field, Default) -> Default;
infer_fact_time(Facts, Field, Default) ->
  Values = [maps:get(Field, Fact, Default) || Fact <- Facts, maps:get(Field, Fact, undefined) =/= undefined],
  case Values of
    [] -> Default;
    _ when Field =:= observed_at -> lists:min(Values);
    _ -> lists:max(Values)
  end.

has_traceable_source(Facts) ->
  lists:any(
    fun (Fact) ->
      SourceUrl = openagentic_case_store_common_lookup:get_bin(Fact, [source_url, sourceUrl], <<>>),
      EvidenceRefs = openagentic_case_store_common_lookup:get_list(Fact, [evidence_refs, evidenceRefs], []),
      SourceUrl =/= <<>> orelse EvidenceRefs =/= []
    end,
    Facts
  ).

parse_json_object(Output0) ->
  Output = string:trim(openagentic_case_store_common_core:to_bin(Output0)),
  Bin = strip_json_code_fences(Output),
  try
    Obj = openagentic_json:decode(Bin),
    case is_map(Obj) of
      true -> {ok, openagentic_case_store_repo_persist:normalize_keys(Obj)};
      false -> {error, not_object}
    end
  catch
    _:_ -> {error, invalid_json}
  end.

strip_json_code_fences(Bin0) ->
  Bin = openagentic_case_store_common_core:to_bin(Bin0),
  case re:run(Bin, <<"(?s)^```[a-zA-Z0-9_-]*\\s*(\\{.*\\})\\s*```\\s*$">>, [{capture, [1], binary}, unicode]) of
    {match, [Inner]} -> Inner;
    _ -> Bin
  end.
