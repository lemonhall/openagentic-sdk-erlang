-module(openagentic_cli_runtime_opts).
-export([runtime_opts/1]).

runtime_opts(Flags0) ->
  Flags = openagentic_cli_values:ensure_map(Flags0),
  %% Kotlin CLI runs as a normal process so cwd is the project directory.
  %% When running this Erlang CLI from `rebar3 shell`, cwd can be under `_build/`.
  %% To reduce surprises, when project dir is not explicitly provided we search upwards
  %% for a `.env` (or `rebar.config`) and treat that directory as project dir.
  ExplicitProjectDir = maps:get(project_dir, Flags, maps:get(cwd, Flags, undefined)),
  ProjectDir0 =
    case ExplicitProjectDir of
      undefined -> openagentic_cli_values:cwd_safe();
      V -> V
    end,
  UsedDefault = ExplicitProjectDir =:= undefined,
  ProjectDir1 = openagentic_cli_values:to_list(string:trim(openagentic_cli_values:to_bin(ProjectDir0))),
  ProjectDir = case UsedDefault of true -> openagentic_cli_project:resolve_project_dir(ProjectDir1); false -> ProjectDir1 end,
  DotEnv = openagentic_dotenv:load(filename:join([ProjectDir, ".env"])),

  ApiKey =
    openagentic_cli_values:first_non_blank([
      maps:get(api_key, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_API_KEY">>, DotEnv),
      os:getenv("OPENAI_API_KEY")
    ]),

  Model =
    openagentic_cli_values:first_non_blank([
      maps:get(model, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_MODEL">>, DotEnv),
      openagentic_dotenv:get(<<"MODEL">>, DotEnv),
      os:getenv("OPENAI_MODEL"),
      os:getenv("MODEL")
    ]),

  BaseUrl =
    openagentic_cli_values:first_non_blank([
      maps:get(base_url, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_BASE_URL">>, DotEnv),
      os:getenv("OPENAI_BASE_URL"),
      <<"https://api.openai.com/v1">>
    ]),

  ApiKeyHeader =
    openagentic_cli_values:first_non_blank([
      maps:get(api_key_header, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_API_KEY_HEADER">>, DotEnv),
      os:getenv("OPENAI_API_KEY_HEADER"),
      <<"authorization">>
    ]),
  Protocol = maps:get(protocol, Flags, responses),
  Stream = maps:get(stream, Flags, true),
  ColorFlag = maps:get(color, Flags, undefined),
  Color =
    case ColorFlag of
      true -> true;
      false -> false;
      _ -> openagentic_cli_ansi:auto_color()
    end,
  RenderMarkdown = openagentic_cli_values:to_bool_default(maps:get(render_markdown, Flags, true), true),
  Permission = maps:get(permission, Flags, default),
  Resume = maps:get(resume_session_id, Flags, undefined),
  MaxSteps = maps:get(max_steps, Flags, 50),
  Compaction = openagentic_cli_values:ensure_map(maps:get(compaction, Flags, #{})),
  OpenAiStore0 =
    case maps:is_key(openai_store, Flags) of
      true -> maps:get(openai_store, Flags);
      false -> openagentic_cli_values:first_non_blank([openagentic_dotenv:get(<<"OPENAI_STORE">>, DotEnv), os:getenv("OPENAI_STORE")])
    end,
  OpenAiStore = openagentic_cli_values:to_bool_default(OpenAiStore0, true),

  UserAnswerer = fun openagentic_cli_project:ask_user_answerer/1,
  Gate =
    case Permission of
      bypass -> openagentic_permissions:bypass();
      deny -> openagentic_permissions:deny();
      prompt -> openagentic_permissions:prompt(UserAnswerer);
      default -> openagentic_permissions:default(UserAnswerer);
      _ -> openagentic_permissions:default(UserAnswerer)
    end,

  Explore = openagentic_built_in_subagents:explore_agent(),
  Research = openagentic_built_in_subagents:research_agent(),
  TaskAgents = [Explore, Research],

  case {ApiKey, Model} of
    {undefined, _} ->
      io:format("Missing API key. Use --api-key, or set OPENAI_API_KEY (env/.env).~n", []),
      halt(2);
    {_, undefined} ->
      io:format("Missing model. Use --model, or set OPENAI_MODEL/MODEL (env/.env).~n", []),
      halt(2);
    _ ->
      ok
  end,

  #{
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    api_key_header => ApiKeyHeader,
    protocol => Protocol,
    include_partial_messages => Stream,
    resume_session_id => Resume,
    max_steps => MaxSteps,
    compaction => Compaction,
    openai_store => OpenAiStore,
    cwd => ProjectDir,
    project_dir => ProjectDir,
    permission_gate => Gate,
    user_answerer => UserAnswerer,
    task_progress_emitter => fun (Msg) -> io:format("~ts~n", [openagentic_cli_values:to_text(Msg)]) end,
    task_agents => TaskAgents,
    event_sink => openagentic_cli_event_sink:event_sink(Stream, #{color => Color, render_markdown => RenderMarkdown})
  }.
