-module(openagentic_e2e_online_runner).
-export([run/0]).

run() ->
  case e2e_enabled() of
    false ->
      {skip, disabled};
    true ->
      try
        RepoRoot = openagentic_e2e_online_utils:repo_root(),
        DotEnv = openagentic_dotenv:load(filename:join([RepoRoot, ".env"])),
        Cfg = openagentic_e2e_online_utils:load_cfg(DotEnv),
        ok = openagentic_e2e_online_utils:ensure_required_cfg(Cfg),
        SessionRoot = openagentic_e2e_online_utils:ensure_list(maps:get(session_root, Cfg)),
        ok = openagentic_e2e_online_utils:ensure_dir(filename:join([SessionRoot, "x"])),
        TmpProject = openagentic_e2e_online_fixtures:make_tmp_project(RepoRoot),
        ok = openagentic_e2e_online_fixtures:write_tmp_project_files(TmpProject),
        ok = openagentic_e2e_online_fixtures:prepare_global_skill(SessionRoot),
        ok = openagentic_e2e_online_fixtures:prepare_global_slash_command(SessionRoot),
        Results =
          openagentic_e2e_online_cases_basic:cases(Cfg, TmpProject) ++
            openagentic_e2e_online_cases_tools:cases(Cfg, TmpProject) ++
            openagentic_e2e_online_cases_webfetch:cases(Cfg, TmpProject),
        classify_results(Results)
      catch
        _:Reason -> {error, Reason}
      end
  end.

e2e_enabled() ->
  case os:getenv("OPENAGENTIC_E2E") of
    "1" -> true;
    "true" -> true;
    "yes" -> true;
    _ -> false
  end.

classify_results(Results) ->
  Errors = [R || R <- Results, is_tuple(R), element(1, R) =:= error],
  Warns = [R || R <- Results, is_tuple(R), element(1, R) =:= warn],
  AllowedWarns = [W || W <- Warns, openagentic_e2e_online_assert:is_allowed_warn(W) =:= true],
  BadWarns = [W || W <- Warns, openagentic_e2e_online_assert:is_allowed_warn(W) =:= false],
  case {Errors, BadWarns, AllowedWarns} of
    {[], [], []} -> ok;
    {[], [], Ws} -> {warn, Ws};
    {Es, Ws, Aws} -> {error, #{errors => Es, warnings => Ws, allowed_warnings => Aws}}
  end.
