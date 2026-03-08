-module(openagentic_skills_api).

-export([get/2, index/1]).

index(ProjectDir0) ->
  ProjectDir = openagentic_skills_utils:ensure_list(ProjectDir0),
  AgentsRoot = openagentic_paths:default_agents_root(),
  GlobalRoot = openagentic_paths:default_session_root(),
  ClaudeRoot = filename:join([ProjectDir, ".claude"]),
  Roots = [AgentsRoot, GlobalRoot, ProjectDir, ClaudeRoot],
  Map =
    lists:foldl(
      fun (Root0, Acc0) ->
        Root = openagentic_skills_utils:ensure_list(Root0),
        Files = openagentic_skills_discovery:iter_skill_files(Root),
        lists:foldl(fun merge_skill/2, Acc0, Files)
      end,
      #{},
      Roots
    ),
  lists:sort(fun (A, B) -> maps:get(name, A) =< maps:get(name, B) end, maps:values(Map)).

merge_skill(Path, Acc0) ->
  case openagentic_skills_discovery:read_skill_file(Path) of
    {ok, Info} ->
      Name = maps:get(name, Info, <<>>),
      case Name of <<>> -> Acc0; _ -> Acc0#{Name => Info} end;
    _ ->
      Acc0
  end.

get(ProjectDir0, Name0) ->
  Name = openagentic_skills_utils:to_bin(Name0),
  Infos = index(ProjectDir0),
  Found = [Info || Info <- Infos, maps:get(name, Info) =:= Name],
  case Found of [One | _] -> {ok, One}; [] -> {error, not_found} end.
