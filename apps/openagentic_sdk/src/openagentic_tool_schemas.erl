-module(openagentic_tool_schemas).

-export([responses_tools/1, responses_tools/2]).

responses_tools(ToolModules) when is_list(ToolModules) ->
  responses_tools(ToolModules, #{}).

responses_tools(ToolModules, Ctx0) when is_list(ToolModules) ->
  Ctx = ensure_map(Ctx0),
  lists:map(fun(Mod) -> tool_to_schema(Mod, Ctx) end, ToolModules).

tool_to_schema(Mod, Ctx) ->
  Name = Mod:name(),
  Desc0 = Mod:description(),
  Desc = maybe_inject_description(Name, Desc0, Ctx),
  Params = tool_params(Mod, Name),
  #{
    type => <<"function">>,
    name => Name,
    description => Desc,
    parameters => Params
  }.

maybe_inject_description(<<"Skill">>, Desc0, Ctx) ->
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  Skills =
    try
      openagentic_skills:index(ProjectDir)
    catch
      _:_ -> []
    end,
  AvailableSkills = render_available_skills(Skills),
  Vars = #{available_skills => AvailableSkills, project_dir => norm_bin(ProjectDir)},
  tool_prompt_or_desc(Desc0, <<"skill">>, Vars);
maybe_inject_description(<<"SlashCommand">>, Desc0, _Ctx) ->
  %% Kotlin parity: no toolprompt resource for SlashCommand; keep the built-in description.
  Desc0;
maybe_inject_description(<<"AskUserQuestion">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"question">>, prompt_vars(Ctx));
maybe_inject_description(<<"Read">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"read">>, prompt_vars(Ctx));
maybe_inject_description(<<"List">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"list">>, prompt_vars(Ctx));
maybe_inject_description(<<"Write">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"write">>, prompt_vars(Ctx));
maybe_inject_description(<<"Edit">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"edit">>, prompt_vars(Ctx));
maybe_inject_description(<<"Glob">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"glob">>, prompt_vars(Ctx));
maybe_inject_description(<<"Grep">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"grep">>, prompt_vars(Ctx));
maybe_inject_description(<<"Bash">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"bash">>, prompt_vars(Ctx));
maybe_inject_description(<<"WebFetch">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"webfetch">>, prompt_vars(Ctx));
maybe_inject_description(<<"WebSearch">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"websearch">>, prompt_vars(Ctx));
maybe_inject_description(<<"Task">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"task">>, prompt_vars(Ctx));
maybe_inject_description(<<"TodoWrite">>, Desc0, Ctx) ->
  tool_prompt_or_desc(Desc0, <<"todowrite">>, prompt_vars(Ctx));
maybe_inject_description(_Name, Desc0, _Ctx) ->
  Desc0.

tool_prompt_or_desc(Desc0, PromptName, Vars) ->
  Prompt = openagentic_tool_prompts:render(PromptName, Vars),
  case byte_size(string:trim(Prompt)) > 0 of
    true -> Prompt;
    false -> to_bin(Desc0)
  end.

render_available_skills(Infos0) ->
  Infos = ensure_list_infos(Infos0),
  Max = 50,
  Infos2 = case length(Infos) > Max of true -> lists:sublist(Infos, Max); false -> Infos end,
  case Infos2 of
    [] -> <<"  (none found)">>;
    _ -> iolist_to_binary(lists:map(fun render_one_skill/1, Infos2))
  end.

prompt_vars(Ctx0) ->
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  Directory = maps:get(directory, Ctx, maps:get(cwd, Ctx, ProjectDir)),
  Agents0 = maps:get(agents, Ctx, maps:get(<<"agents">>, Ctx, undefined)),
  Agents1 = string:trim(to_bin(Agents0)),
  Agents = case Agents1 of <<>> -> <<"  (none configured)">>; <<"undefined">> -> <<"  (none configured)">>; _ -> Agents1 end,
  #{
    directory => norm_bin(Directory),
    project_dir => norm_bin(ProjectDir),
    maxBytes => 1048576,
    maxLines => 2000,
    agents => Agents
  }.

render_one_skill(Info0) ->
  Info = ensure_map(Info0),
  Name = to_bin(maps:get(name, Info, <<>>)),
  Desc0 = to_bin(maps:get(description, Info, <<>>)),
  Desc =
    case byte_size(string:trim(Desc0)) > 0 of
      true -> Desc0;
      false -> <<>>
    end,
  case Desc of
    <<>> ->
      [
        <<"  <skill>\n">>,
        <<"    <name>">>, Name, <<"</name>\n">>,
        <<"    <description />\n">>,
        <<"  </skill>\n">>
      ];
    _ ->
      [
        <<"  <skill>\n">>,
        <<"    <name>">>, Name, <<"</name>\n">>,
        <<"    <description>">>, Desc, <<"</description>\n">>,
        <<"  </skill>\n">>
      ]
  end.

ensure_list_infos(L) when is_list(L) -> L;
ensure_list_infos(_) -> [].

tool_params(_Mod, <<"AskUserQuestion">>) ->
  #{
    type => <<"object">>,
    properties => #{
      questions =>
        #{
          type => <<"array">>,
          items =>
            #{
              type => <<"object">>,
              properties =>
                #{
                  question => #{type => <<"string">>},
                  header => #{type => <<"string">>},
                  options =>
                    #{
                      type => <<"array">>,
                      items =>
                        #{
                          type => <<"object">>,
                          properties => #{label => #{type => <<"string">>}, description => #{type => <<"string">>}},
                          required => [<<"label">>]
                        }
                    },
                  multiple => #{type => <<"boolean">>},
                  multiSelect => #{type => <<"boolean">>}
                },
              required => [<<"question">>]
            }
        },
      question => #{type => <<"string">>},
      options => #{type => <<"array">>, items => #{type => <<"string">>}},
      choices => #{type => <<"array">>, items => #{type => <<"string">>}},
      answers => #{type => <<"object">>}
    },
    required => []
  };
tool_params(_Mod, <<"Read">>) ->
  #{
    type => <<"object">>,
    properties => #{
      file_path => #{type => <<"string">>},
      filePath => #{type => <<"string">>},
      offset => #{type => <<"integer">>},
      limit => #{type => <<"integer">>}
    },
    required => []
  };
tool_params(_Mod, <<"List">>) ->
  #{
    type => <<"object">>,
    properties => #{
      path => #{type => <<"string">>},
      dir => #{type => <<"string">>},
      directory => #{type => <<"string">>}
    },
    required => []
  };
tool_params(_Mod, <<"Write">>) ->
  #{
    type => <<"object">>,
    properties => #{
      file_path => #{type => <<"string">>},
      filePath => #{type => <<"string">>},
      content => #{type => <<"string">>},
      overwrite => #{type => <<"boolean">>}
    },
    required => []
  };
tool_params(_Mod, <<"Edit">>) ->
  #{
    type => <<"object">>,
    properties => #{
      file_path => #{type => <<"string">>},
      filePath => #{type => <<"string">>},
      old => #{type => <<"string">>},
      new => #{type => <<"string">>},
      old_string => #{type => <<"string">>},
      new_string => #{type => <<"string">>},
      oldString => #{type => <<"string">>},
      newString => #{type => <<"string">>},
      count => #{type => <<"integer">>},
      replace_all => #{type => <<"boolean">>},
      replaceAll => #{type => <<"boolean">>},
      before => #{type => <<"string">>},
      'after' => #{type => <<"string">>}
    },
    required => []
  };
tool_params(_Mod, <<"Glob">>) ->
  #{
    type => <<"object">>,
    properties => #{
      pattern => #{type => <<"string">>},
      root => #{type => <<"string">>}
    },
    required => [<<"pattern">>]
  };
tool_params(_Mod, <<"Grep">>) ->
  #{
    type => <<"object">>,
    properties => #{
      query => #{type => <<"string">>},
      file_glob => #{type => <<"string">>},
      root => #{type => <<"string">>},
      case_sensitive => #{type => <<"boolean">>}
    },
    required => [<<"query">>]
  };
tool_params(_Mod, <<"Bash">>) ->
  #{
    type => <<"object">>,
    properties => #{
      command => #{type => <<"string">>},
      workdir => #{type => <<"string">>},
      timeout => #{type => <<"integer">>},
      timeout_s => #{type => <<"number">>}
    },
    required => [<<"command">>]
  };
tool_params(_Mod, <<"WebSearch">>) ->
  #{
    type => <<"object">>,
    properties => #{
      query => #{type => <<"string">>},
      max_results => #{type => <<"integer">>},
      allowed_domains => #{type => <<"array">>, items => #{type => <<"string">>}},
      blocked_domains => #{type => <<"array">>, items => #{type => <<"string">>}}
    },
    required => [<<"query">>]
  };
tool_params(_Mod, <<"WebFetch">>) ->
  #{
    type => <<"object">>,
    properties => #{
      url => #{type => <<"string">>},
      headers => #{type => <<"object">>},
      mode => #{
        type => <<"string">>,
        enum => [<<"markdown">>, <<"clean_html">>, <<"text">>, <<"raw">>]
      },
      max_chars => #{type => <<"integer">>, minimum => 1000, maximum => 80000},
      prompt => #{type => <<"string">>}
    },
    required => [<<"url">>]
  };
tool_params(_Mod, <<"Skill">>) ->
  #{
    type => <<"object">>,
    properties => #{
      name => #{type => <<"string">>}
    },
    required => [<<"name">>]
  };
tool_params(_Mod, <<"SlashCommand">>) ->
  #{
    type => <<"object">>,
    properties => #{
      name => #{type => <<"string">>},
      args => #{type => <<"string">>},
      arguments => #{type => <<"string">>},
      project_dir => #{type => <<"string">>}
    },
    required => [<<"name">>]
  };
tool_params(_Mod, <<"NotebookEdit">>) ->
  #{
    type => <<"object">>,
    properties => #{
      notebook_path => #{type => <<"string">>},
      cell_id => #{type => <<"string">>},
      new_source => #{type => <<"string">>},
      cell_type => #{type => <<"string">>, enum => [<<"code">>, <<"markdown">>]},
      edit_mode => #{type => <<"string">>, enum => [<<"replace">>, <<"insert">>, <<"delete">>]}
    },
    required => [<<"notebook_path">>]
  };
tool_params(_Mod, <<"lsp">>) ->
  #{
    type => <<"object">>,
    properties => #{
      operation =>
        #{
          type => <<"string">>,
          enum =>
            [
              <<"goToDefinition">>,
              <<"findReferences">>,
              <<"hover">>,
              <<"documentSymbol">>,
              <<"workspaceSymbol">>,
              <<"goToImplementation">>,
              <<"prepareCallHierarchy">>,
              <<"incomingCalls">>,
              <<"outgoingCalls">>
            ]
        },
      filePath => #{type => <<"string">>},
      file_path => #{type => <<"string">>},
      line => #{type => <<"integer">>, minimum => 1},
      character => #{type => <<"integer">>, minimum => 1}
    },
    required => [<<"operation">>, <<"filePath">>, <<"line">>, <<"character">>]
  };
tool_params(_Mod, <<"Task">>) ->
  #{
    type => <<"object">>,
    properties => #{
      agent => #{type => <<"string">>},
      prompt => #{type => <<"string">>}
    },
    required => [<<"agent">>, <<"prompt">>]
  };
tool_params(_Mod, <<"TodoWrite">>) ->
  #{
    type => <<"object">>,
    properties => #{
      todos =>
        #{
          type => <<"array">>,
          items =>
            #{
              type => <<"object">>,
              properties =>
                #{
                  content => #{type => <<"string">>},
                  status => #{type => <<"string">>, enum => [<<"pending">>, <<"in_progress">>, <<"completed">>]},
                  activeForm => #{type => <<"string">>}
                },
              required => [<<"content">>, <<"status">>, <<"activeForm">>]
            }
        }
    },
    required => [<<"todos">>]
  };
tool_params(_Mod, _Name) ->
  %% Default to "any object" until we port full schemas.
  #{
    type => <<"object">>,
    properties => #{},
    required => []
  }.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

norm_bin(Path0) ->
  Path = ensure_list(Path0),
  iolist_to_binary(string:replace(filename:absname(Path), "\\", "/", all)).

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
