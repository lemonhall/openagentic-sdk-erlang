-module(openagentic_tool_schemas_descriptions).

-export([maybe_inject_description/3]).

maybe_inject_description(<<"Skill">>, Desc0, Ctx) ->
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  Skills =
    try
      openagentic_skills:index(ProjectDir)
    catch
      _:_ -> []
    end,
  AvailableSkills = render_available_skills(Skills),
  Vars = #{available_skills => AvailableSkills, project_dir => openagentic_tool_schemas_utils:norm_bin(ProjectDir)},
  tool_prompt_or_desc(Desc0, <<"skill">>, Vars);
maybe_inject_description(<<"SlashCommand">>, Desc0, _Ctx) ->
  Desc0;
maybe_inject_description(<<"AskUserQuestion">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"question">>, prompt_vars(Ctx));
maybe_inject_description(<<"Read">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"read">>, prompt_vars(Ctx));
maybe_inject_description(<<"List">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"list">>, prompt_vars(Ctx));
maybe_inject_description(<<"Write">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"write">>, prompt_vars(Ctx));
maybe_inject_description(<<"Edit">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"edit">>, prompt_vars(Ctx));
maybe_inject_description(<<"Glob">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"glob">>, prompt_vars(Ctx));
maybe_inject_description(<<"Grep">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"grep">>, prompt_vars(Ctx));
maybe_inject_description(<<"Bash">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"bash">>, prompt_vars(Ctx));
maybe_inject_description(<<"WebFetch">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"webfetch">>, prompt_vars(Ctx));
maybe_inject_description(<<"WebSearch">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"websearch">>, prompt_vars(Ctx));
maybe_inject_description(<<"Task">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"task">>, prompt_vars(Ctx));
maybe_inject_description(<<"TodoWrite">>, Desc0, Ctx) -> tool_prompt_or_desc(Desc0, <<"todowrite">>, prompt_vars(Ctx));
maybe_inject_description(_Name, Desc0, _Ctx) -> Desc0.

tool_prompt_or_desc(Desc0, PromptName, Vars) ->
  Prompt = openagentic_tool_prompts:render(PromptName, Vars),
  case byte_size(string:trim(Prompt)) > 0 of
    true -> Prompt;
    false -> openagentic_tool_schemas_utils:to_bin(Desc0)
  end.

render_available_skills(Infos0) ->
  Infos = ensure_list_infos(Infos0),
  Infos2 = case length(Infos) > 50 of true -> lists:sublist(Infos, 50); false -> Infos end,
  case Infos2 of
    [] -> <<"  (none found)">>;
    _ -> iolist_to_binary(lists:map(fun render_one_skill/1, Infos2))
  end.

prompt_vars(Ctx0) ->
  Ctx = openagentic_tool_schemas_utils:ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir0 = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, undefined)),
  WorkspaceDir1 = string:trim(openagentic_tool_schemas_utils:to_bin(WorkspaceDir0)),
  WorkspaceDir = case WorkspaceDir1 of <<>> -> <<"  (none)">>; <<"undefined">> -> <<"  (none)">>; _ -> WorkspaceDir1 end,
  Directory = maps:get(directory, Ctx, maps:get(cwd, Ctx, ProjectDir)),
  Agents0 = maps:get(agents, Ctx, maps:get(<<"agents">>, Ctx, undefined)),
  Agents1 = string:trim(openagentic_tool_schemas_utils:to_bin(Agents0)),
  Agents = case Agents1 of <<>> -> <<"  (none configured)">>; <<"undefined">> -> <<"  (none configured)">>; _ -> Agents1 end,
  #{
    directory => openagentic_tool_schemas_utils:norm_bin(Directory),
    project_dir => openagentic_tool_schemas_utils:norm_bin(ProjectDir),
    workspace_dir => case WorkspaceDir of <<"  (none)">> -> WorkspaceDir; _ -> openagentic_tool_schemas_utils:norm_bin(WorkspaceDir) end,
    maxBytes => 1048576,
    maxLines => 2000,
    agents => Agents
  }.

render_one_skill(Info0) ->
  Info = openagentic_tool_schemas_utils:ensure_map(Info0),
  Name = openagentic_tool_schemas_utils:to_bin(maps:get(name, Info, <<>>)),
  Desc0 = openagentic_tool_schemas_utils:to_bin(maps:get(description, Info, <<>>)),
  Desc = case byte_size(string:trim(Desc0)) > 0 of true -> Desc0; false -> <<>> end,
  case Desc of
    <<>> -> [<<"  <skill>\n">>, <<"    <name>">>, Name, <<"</name>\n">>, <<"    <description />\n">>, <<"  </skill>\n">>];
    _ -> [<<"  <skill>\n">>, <<"    <name>">>, Name, <<"</name>\n">>, <<"    <description>">>, Desc, <<"</description>\n">>, <<"  </skill>\n">>]
  end.

ensure_list_infos(List) when is_list(List) -> List;
ensure_list_infos(_) -> [].
