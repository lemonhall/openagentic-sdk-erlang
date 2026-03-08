-module(openagentic_case_store_run_runtime_opts).
-export([build_monitoring_runtime_opts/7, normalize_runtime_opts/1, normalize_provider_mod/1]).

build_monitoring_runtime_opts(RootDir, CaseDir, Task, ScratchDir, ExecutionSessionId, AllowedTools, Input) ->
  RuntimeOpts0 = openagentic_case_store_common_core:ensure_map(openagentic_case_store_common_lookup:get_in_map(Input, [runtime_opts], openagentic_case_store_common_lookup:get_in_map(Input, [runtimeOpts], #{}))),
  RuntimeOpts1 = normalize_runtime_opts(RuntimeOpts0),
  TaskWorkspaceDir = openagentic_case_store_run_context:task_workspace_dir(CaseDir, Task),
  BaseOpts =
    openagentic_case_store_common_meta:compact_map(
      #{
        session_root => RootDir,
        project_dir =>
          case openagentic_case_store_common_lookup:find_any(RuntimeOpts1, [project_dir, projectDir]) of
            undefined -> RootDir;
            ProjectDir -> ProjectDir
          end,
        cwd =>
          case openagentic_case_store_common_lookup:find_any(RuntimeOpts1, [cwd]) of
            undefined -> TaskWorkspaceDir;
            Cwd -> Cwd
          end,
        resume_session_id => ExecutionSessionId,
        workspace_dir => TaskWorkspaceDir,
        scratch_dir => ScratchDir,
        tools =>
          case openagentic_case_store_common_lookup:find_any(RuntimeOpts1, [tools]) of
            undefined -> [];
            ToolMods -> ToolMods
          end,
        permission_gate =>
          case openagentic_case_store_common_lookup:find_any(RuntimeOpts1, [permission_gate, permissionGate]) of
            undefined -> openagentic_permissions:default(undefined);
            PermissionGate -> PermissionGate
          end,
        allowed_tools => AllowedTools,
        strict_unknown_fields => true
      }
    ),
  maps:merge(RuntimeOpts1, BaseOpts).

normalize_runtime_opts(RuntimeOpts0) ->
  RuntimeOpts = openagentic_case_store_common_core:ensure_map(RuntimeOpts0),
  case openagentic_case_store_common_lookup:find_any(RuntimeOpts, [provider_mod, providerMod]) of
    undefined -> RuntimeOpts;
    ProviderMod -> RuntimeOpts#{provider_mod => normalize_provider_mod(ProviderMod)}
  end.

normalize_provider_mod(ProviderMod) when is_atom(ProviderMod) -> ProviderMod;
normalize_provider_mod(ProviderMod) ->
  ProviderModBin = openagentic_case_store_common_core:trim_bin(openagentic_case_store_common_core:to_bin(ProviderMod)),
  case ProviderModBin of
    <<>> -> ProviderMod;
    _ ->
      try binary_to_existing_atom(ProviderModBin, utf8) of
        Mod -> Mod
      catch
        error:badarg -> ProviderMod
      end
  end.
