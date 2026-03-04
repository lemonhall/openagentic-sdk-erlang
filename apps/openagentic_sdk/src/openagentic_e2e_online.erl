-module(openagentic_e2e_online).

-export([suite/0]).

%% Online E2E suite (real provider).
%%
%% Safety:
%% - Never prints API keys or .env contents
%% - Uses a temporary project dir under `.tmp/` so file tools cannot access repo `.env`
%% - Requires explicit opt-in via OPENAGENTIC_E2E=1

suite() ->
  case os:getenv("OPENAGENTIC_E2E") of
    "1" -> ok;
    "true" -> ok;
    "yes" -> ok;
    _ ->
      io:format("E2E disabled. Set OPENAGENTIC_E2E=1 to run online tests.~n", []),
      erlang:halt(2)
  end,

  RepoRoot = repo_root(),
  DotEnv = openagentic_dotenv:load(filename:join([RepoRoot, ".env"])),
  Cfg = load_cfg(DotEnv),
  ok = ensure_required_cfg(Cfg),

  SessionRoot = ensure_list(maps:get(session_root, Cfg)),
  ok = ensure_dir(filename:join([SessionRoot, "x"])),

  %% Prepare safe temp project dir (so Read/List/Grep/Glob cannot reach repo secrets).
  TmpProject = make_tmp_project(RepoRoot),
  ok = write_tmp_project_files(TmpProject),

  %% Prepare global skill + slash command templates outside repo.
  ok = prepare_global_skill(SessionRoot),
  ok = prepare_global_slash_command(SessionRoot),

  %% Run cases.
  Results = [
    case_basic_pong(Cfg, TmpProject),
    case_streaming_deltas(Cfg, TmpProject),
    case_session_resume(Cfg, TmpProject),
    case_tools_responses_best_effort(Cfg, TmpProject),
    case_tools_list_read_grep_glob(Cfg, TmpProject),
    case_skill_responses_best_effort(Cfg, TmpProject),
    case_skill_tool(Cfg, TmpProject),
    case_slash_command_responses_tool(Cfg, TmpProject),
    case_slash_command_tool(Cfg, TmpProject),
    case_webfetch_responses_tool(Cfg, TmpProject),
    case_webfetch_tool(Cfg, TmpProject)
  ],
  Errors = [R || R <- Results, is_tuple(R), element(1, R) =:= error],
  Warns = [R || R <- Results, is_tuple(R), element(1, R) =:= warn],
  AllowedWarns = [W || W <- Warns, is_allowed_warn(W) =:= true],
  BadWarns = [W || W <- Warns, is_allowed_warn(W) =:= false],
  case {Errors, BadWarns, AllowedWarns} of
    {[], [], []} ->
      io:format("E2E suite OK (~p cases).~n", [length(Results)]),
      ok;
    {[], [], Ws} ->
      io:format("E2E suite OK with allowed warnings: ~p~n", [Ws]),
      ok;
    {Es, Ws, Aws} ->
      io:format("E2E suite FAILED: errors=~p warnings=~p allowed_warnings=~p~n", [Es, Ws, Aws]),
      erlang:halt(1)
  end.

%% ---- cases ----

case_basic_pong(Cfg, TmpProject) ->
  Prompt = <<"Reply with exactly: pong">>,
  Opts =
    base_runtime_opts(Cfg, TmpProject, #{
      include_partial_messages => false,
      tools => []
    }),
  {Res, _Events} = run_query(Prompt, Opts),
  assert_ok_text_contains(basic_pong, Res, <<"pong">>).

case_streaming_deltas(Cfg, TmpProject) ->
  Prompt = <<"Write 120 characters of 'a', then a newline, then END.">>,
  Opts =
    base_runtime_opts(Cfg, TmpProject, #{
      include_partial_messages => true,
      tools => []
    }),
  {Res, Events} = run_query(Prompt, Opts),
  case {assert_ok_non_empty(streaming_result, Res), has_event_type(Events, <<"assistant.delta">>)} of
    {ok, true} ->
      ok;
    {ok, false} ->
      %% Some gateways/providers return only a completed message even when `stream=true`.
      {warn, {streaming_no_deltas, events_summary(Events)}};
    {Err, _} ->
      Err
  end.

case_session_resume(Cfg, TmpProject) ->
  {Res1, _} =
    run_query(
      <<"Remember the number 42. Reply only: OK">>,
      base_runtime_opts(Cfg, TmpProject, #{include_partial_messages => false, tools => []})
    ),
  case Res1 of
    {ok, #{session_id := Sid}} ->
      Opts2 = base_runtime_opts(Cfg, TmpProject, #{include_partial_messages => false, tools => [], resume_session_id => Sid}),
      {Res2, _} = run_query(<<"What number did I ask you to remember? Reply with just the number.">>, Opts2),
      assert_ok_text_contains(resume, Res2, <<"42">>);
    _ ->
      {error, {resume_missing_session_id, Res1}}
  end.

case_tools_list_read_grep_glob(Cfg, TmpProject) ->
  NonceLine = expected_nonce_line(TmpProject),
  ToolMods = [
    openagentic_tool_list,
    openagentic_tool_read,
    openagentic_tool_grep,
    openagentic_tool_glob
  ],
  Prompt =
    <<
      "Automated test. Do the following using tools:\n"
      "1) List directory '.' with limit 20.\n"
      "2) Read file 'nonce.txt'.\n"
      "3) Grep for 'needle' in '.'\n"
      "4) Glob for '**/*.txt'\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the exact contents of nonce.txt (trim the trailing newline)\n"
      "- Line 2: TOOLS_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>],
        max_steps => 12,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(tools_ok, Res, <<"TOOLS_OK">>),
    assert_ok_text_contains(tools_nonce, Res, NonceLine),
    tool_events_ok_with_results(Events, [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>])
  ]).

case_tools_responses_best_effort(Cfg, TmpProject) ->
  NonceLine = expected_nonce_line(TmpProject),
  ToolMods = [
    openagentic_tool_list,
    openagentic_tool_read,
    openagentic_tool_grep,
    openagentic_tool_glob
  ],
  Prompt =
    <<
      "Automated test. Do the following using tools:\n"
      "1) List directory '.' with limit 20.\n"
      "2) Read file 'nonce.txt'.\n"
      "3) Grep for 'needle' in '.'\n"
      "4) Glob for '**/*.txt'\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the exact contents of nonce.txt (trim the trailing newline)\n"
      "- Line 2: TOOLS_R_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>],
        max_steps => 12,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(tools_r_ok, Res, <<"TOOLS_R_OK">>),
    assert_ok_text_contains(tools_r_nonce, Res, NonceLine),
    tool_events_ok_with_results(Events, [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>])
  ]).

case_skill_tool(Cfg, TmpProject) ->
  MarkerLine = expected_skill_marker_line(Cfg),
  ToolMods = [openagentic_tool_skill],
  Prompt =
    <<
      "Automated test. Use the Skill tool to load the skill named 'e2e-skill'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the skill (starts with MARKER=)\n"
      "- Line 2: SKILL_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"Skill">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(skill_ok, Res, <<"SKILL_OK">>),
    assert_ok_text_contains(skill_marker, Res, MarkerLine),
    tool_events_ok_with_results(Events, [<<"Skill">>])
  ]).

case_skill_responses_best_effort(Cfg, TmpProject) ->
  MarkerLine = expected_skill_marker_line(Cfg),
  ToolMods = [openagentic_tool_skill],
  Prompt =
    <<
      "Automated test. Use the Skill tool to load the skill named 'e2e-skill'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the skill (starts with MARKER=)\n"
      "- Line 2: SKILL_R_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"Skill">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(skill_r_ok, Res, <<"SKILL_R_OK">>),
    assert_ok_text_contains(skill_r_marker, Res, MarkerLine),
    tool_events_ok_with_results(Events, [<<"Skill">>])
  ]).

case_slash_command_responses_tool(Cfg, TmpProject) ->
  MarkerLine = expected_slash_command_marker_line(Cfg),
  ToolMods = [openagentic_tool_slash_command],
  Prompt =
    <<
      "Automated test. Use the SlashCommand tool to load command template named 'e2e'.\n"
      "Pass args: 'abc'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the rendered command output (starts with MARKER=)\n"
      "- Line 2: CMD_R_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"SlashCommand">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(cmd_r_ok, Res, <<"CMD_R_OK">>),
    assert_ok_text_contains(cmd_r_marker, Res, MarkerLine),
    tool_events_ok_with_results(Events, [<<"SlashCommand">>])
  ]).

case_slash_command_tool(Cfg, TmpProject) ->
  MarkerLine = expected_slash_command_marker_line(Cfg),
  ToolMods = [openagentic_tool_slash_command],
  Prompt =
    <<
      "Automated test. Use the SlashCommand tool to load command template named 'e2e'.\n"
      "Pass args: 'abc'.\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the marker line from the rendered command output (starts with MARKER=)\n"
      "- Line 2: CMD_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"SlashCommand">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(cmd_ok, Res, <<"CMD_OK">>),
    assert_ok_text_contains(cmd_marker, Res, MarkerLine),
    tool_events_ok_with_results(Events, [<<"SlashCommand">>])
  ]).

case_webfetch_responses_tool(Cfg, TmpProject) ->
  ToolMods = [openagentic_tool_webfetch],
  Prompt =
    <<
      "Automated test. Use WebFetch tool to fetch https://example.com/ with mode 'text'.\n"
      "Then reply only: WEB_R_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"WebFetch">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(web_r_ok, Res, <<"WEB_R_OK">>),
    tool_events_ok_with_results(Events, [<<"WebFetch">>])
  ]).

case_webfetch_tool(Cfg, TmpProject) ->
  ToolMods = [openagentic_tool_webfetch],
  Prompt =
    <<
      "Automated test. Use WebFetch tool to fetch https://example.com/ with mode 'text'.\n"
      "Then reply only: WEB_OK\n"
    >>,
  Opts =
    base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"WebFetch">>],
        max_steps => 8,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = run_query(Prompt, Opts),
  first_error([
    assert_ok_text_contains(web_ok, Res, <<"WEB_OK">>),
    tool_events_ok_with_results(Events, [<<"WebFetch">>])
  ]).

%% ---- runtime helpers ----

run_query(Prompt, Opts0) ->
  Ref = make_ref(),
  _ = erlang:put({e2e_events, Ref}, []),
  Sink =
    fun (Ev) ->
      Acc0 = erlang:get({e2e_events, Ref}),
      Acc = case is_list(Acc0) of true -> Acc0; false -> [] end,
      erlang:put({e2e_events, Ref}, [Ev | Acc]),
      ok
    end,
  Opts = (ensure_map(Opts0))#{event_sink => Sink},
  Res =
    try
      openagentic_runtime:query(Prompt, Opts)
    catch
      _:T -> {error, {crash, T}}
    end,
  Events0 = erlang:get({e2e_events, Ref}),
  _ = erlang:erase({e2e_events, Ref}),
  Events = lists:reverse(ensure_list(Events0)),
  {Res, Events}.

base_runtime_opts(Cfg, TmpProject, Extra0) ->
  Extra = ensure_map(Extra0),
  Base = #{
    %% Provider config:
    api_key => maps:get(api_key, Cfg),
    model => maps:get(model, Cfg),
    base_url => maps:get(base_url, Cfg),
    api_key_header => maps:get(api_key_header, Cfg),
    protocol => responses,
    openai_store => maps:get(openai_store, Cfg, true),

    %% IO roots:
    session_root => maps:get(session_root, Cfg),
    cwd => TmpProject,
    project_dir => TmpProject,

    %% Keep suite bounded:
    timeout_ms => maps:get(timeout_ms, Cfg, 60000),
    max_steps => 20
  },
  maps:merge(Base, Extra).

%% ---- assertions ----

assert_ok_non_empty(Tag, Res) ->
  case Res of
    {ok, #{final_text := Txt}} ->
      case byte_size(string:trim(to_bin(Txt))) > 0 of
        true -> ok;
        false -> {error, {Tag, empty_text}}
      end;
    Other ->
      {error, {Tag, Other}}
  end.

assert_ok_text_contains(Tag, Res, Needle) ->
  case Res of
    {ok, #{final_text := Txt}} ->
      T = to_bin(Txt),
      case binary:match(string:lowercase(T), string:lowercase(to_bin(Needle))) of
        nomatch -> {error, {Tag, not_found}};
        _ -> ok
      end;
    Other ->
      {error, {Tag, Other}}
  end.

first_error([]) -> ok;
first_error([ok | Rest]) -> first_error(Rest);
first_error([Err | _]) -> Err.

has_event_type(Events, Type) ->
  lists:any(fun (Ev0) -> event_type(Ev0) =:= Type end, ensure_list(Events)).

event_type(Ev0) ->
  Ev = ensure_map(Ev0),
  to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))).

tool_events_ok_with_results(Events0, ToolNames0) ->
  Events = ensure_list(Events0),
  ToolNames = [to_bin(N) || N <- ensure_list(ToolNames0)],
  UsePairs =
    [
      {to_bin(maps:get(name, E)), to_bin(maps:get(tool_use_id, E))}
    ||
      E0 <- Events,
      E <- [ensure_map(E0)],
      event_type(E) =:= <<"tool.use">>,
      maps:is_key(name, E),
      maps:is_key(tool_use_id, E)
    ],
  UsedNames = lists:usort([N || {N, _} <- UsePairs]),
  Missing = [N || N <- ToolNames, not lists:member(N, UsedNames)],
  case Missing of
    [] ->
      OkResultIds =
        lists:usort(
          [
            to_bin(maps:get(tool_use_id, E))
          ||
            E0 <- Events,
            E <- [ensure_map(E0)],
            event_type(E) =:= <<"tool.result">>,
            maps:get(is_error, E, true) =:= false,
            maps:is_key(tool_use_id, E)
          ]
        ),
      Bad =
        [
          #{tool => ToolName, error => missing_ok_result}
        ||
          ToolName <- ToolNames,
          not lists:any(fun ({N, Id}) -> N =:= ToolName andalso lists:member(Id, OkResultIds) end, UsePairs)
        ],
      case Bad of
        [] -> ok;
        _ -> {error, #{error => tool_result_missing_or_error, details => Bad}}
      end;
    _ ->
      {error, #{error => missing_tool_use_events, missing => Missing, used => UsedNames, summary => events_summary(Events)}}
  end.

is_allowed_warn({warn, {streaming_no_deltas, _}}) -> true;
is_allowed_warn(_) -> false.

events_summary(Events) ->
  Types = [event_type(E) || E <- ensure_list(Events)],
  lists:usort(Types).

%% ---- setup helpers ----

prepare_global_skill(SessionRoot0) ->
  SessionRoot = ensure_list(SessionRoot0),
  Dir = filename:join([SessionRoot, "skills", "e2e-skill"]),
  ok = ensure_dir(filename:join([Dir, "x"])),
  Path = filename:join([Dir, "SKILL.md"]),
  Marker = rand_hex(16),
  Body =
    <<
      "---\n"
      "name: e2e-skill\n"
      "description: online e2e skill\n"
      "---\n"
      "\n"
      "# e2e-skill\n"
      "\n"
      "This is a generated skill for online E2E.\n"
      "\n"
      "MARKER=", Marker/binary, "\n"
    >>,
  ok = file:write_file(Path, Body),
  ok.

prepare_global_slash_command(SessionRoot0) ->
  SessionRoot = ensure_list(SessionRoot0),
  Conf = filename:join([SessionRoot, "opencode-config"]),
  ok = ensure_dir(filename:join([Conf, "x"])),
  true = os:putenv("OPENCODE_CONFIG_DIR", Conf),
  CmdDir = filename:join([Conf, "commands"]),
  ok = ensure_dir(filename:join([CmdDir, "x"])),
  Path = filename:join([CmdDir, "e2e.md"]),
  Marker = rand_hex(16),
  Body =
    <<
      "# e2e\n"
      "\n"
      "MARKER=", Marker/binary, "\n"
      "args=${args}\n"
      "path=${path}\n"
    >>,
  ok = file:write_file(Path, Body),
  ok.

make_tmp_project(RepoRoot0) ->
  RepoRoot = ensure_list(RepoRoot0),
  Base = filename:join([RepoRoot, ".tmp", "e2e-online-project"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(millisecond), erlang:unique_integer([positive, monotonic])])),
  Dir = filename:join([Base, Id]),
  ok = ensure_dir(filename:join([Dir, "x"])),
  Dir.

write_tmp_project_files(Dir0) ->
  Dir = ensure_list(Dir0),
  Nonce = rand_hex(16),
  ok = file:write_file(filename:join([Dir, "hello.txt"]), <<"hello world\nneedle here\n">>),
  ok = file:write_file(filename:join([Dir, "notes.txt"]), <<"some notes\n">>),
  ok = file:write_file(filename:join([Dir, "nonce.txt"]), <<"NONCE=", Nonce/binary, "\n">>),
  SrcDir = filename:join([Dir, "src"]),
  ok = ensure_dir(filename:join([SrcDir, "x"])),
  ok = file:write_file(filename:join([SrcDir, "a.txt"]), <<"alpha\n">>),
  ok.

expected_nonce_line(TmpProject0) ->
  TmpProject = ensure_list(TmpProject0),
  Path = filename:join([TmpProject, "nonce.txt"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      Line = string:trim(to_bin(Bin)),
      case byte_size(Line) > 0 of true -> Line; false -> <<"MISSING_NONCE">> end;
    _ ->
      <<"MISSING_NONCE">>
  end.

expected_skill_marker_line(Cfg0) ->
  Cfg = ensure_map(Cfg0),
  SessionRoot = ensure_list(maps:get(session_root, Cfg)),
  Path = filename:join([SessionRoot, "skills", "e2e-skill", "SKILL.md"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      case extract_line_with_prefix(Bin, <<"MARKER=">>) of
        {ok, Line} -> Line;
        _ -> <<"MISSING_MARKER_SKILL">>
      end;
    _ ->
      <<"MISSING_MARKER_SKILL">>
  end.

expected_slash_command_marker_line(Cfg0) ->
  Cfg = ensure_map(Cfg0),
  SessionRoot = ensure_list(maps:get(session_root, Cfg)),
  Path = filename:join([SessionRoot, "opencode-config", "commands", "e2e.md"]),
  case file:read_file(Path) of
    {ok, Bin} ->
      case extract_line_with_prefix(Bin, <<"MARKER=">>) of
        {ok, Line} -> Line;
        _ -> <<"MISSING_MARKER_CMD">>
      end;
    _ ->
      <<"MISSING_MARKER_CMD">>
  end.

extract_line_with_prefix(Text0, Prefix0) ->
  Text = to_bin(Text0),
  Prefix = to_bin(Prefix0),
  Lines = binary:split(Text, <<"\n">>, [global]),
  case [string:trim(L, trailing, "\r") || L <- Lines, starts_with(L, Prefix)] of
    [Line | _] -> {ok, to_bin(Line)};
    [] -> {error, not_found}
  end.

starts_with(Bin0, Prefix0) ->
  Bin = to_bin(Bin0),
  Prefix = to_bin(Prefix0),
  Bs = byte_size(Bin),
  Ps = byte_size(Prefix),
  Bs >= Ps andalso binary:part(Bin, 0, Ps) =:= Prefix.

repo_root() ->
  case file:get_cwd() of
    {ok, Cwd} -> Cwd;
    _ -> "."
  end.

load_cfg(DotEnv) ->
  ApiKey = first_non_blank([openagentic_dotenv:get(<<"OPENAI_API_KEY">>, DotEnv), os:getenv("OPENAI_API_KEY")]),
  Model =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_MODEL">>, DotEnv),
      openagentic_dotenv:get(<<"MODEL">>, DotEnv),
      os:getenv("OPENAI_MODEL"),
      os:getenv("MODEL")
    ]),
  BaseUrl =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_BASE_URL">>, DotEnv),
      os:getenv("OPENAI_BASE_URL"),
      <<"https://api.openai.com/v1">>
    ]),
  ApiKeyHeader =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_API_KEY_HEADER">>, DotEnv),
      os:getenv("OPENAI_API_KEY_HEADER"),
      <<"authorization">>
    ]),
  Store0 =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_STORE">>, DotEnv),
      os:getenv("OPENAI_STORE")
    ]),
  Store = to_bool(Store0, true),
  SessionRoot = ensure_list(openagentic_paths:default_session_root()),
  #{
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    api_key_header => ApiKeyHeader,
    openai_store => Store,
    session_root => SessionRoot,
    timeout_ms => 60000
  }.

ensure_required_cfg(Cfg) ->
  case {maps:get(api_key, Cfg, undefined), maps:get(model, Cfg, undefined), maps:get(base_url, Cfg, undefined)} of
    {undefined, _, _} -> erlang:error(missing_api_key);
    {_, undefined, _} -> erlang:error(missing_model);
    {_, _, undefined} -> erlang:error(missing_base_url);
    _ -> ok
  end.

first_non_blank([]) -> undefined;
first_non_blank([false | Rest]) -> first_non_blank(Rest);
first_non_blank([undefined | Rest]) -> first_non_blank(Rest);
first_non_blank([null | Rest]) -> first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V = string:trim(to_bin(V0)),
  case V of
    <<>> -> first_non_blank(Rest);
    <<"undefined">> -> first_non_blank(Rest);
    _ -> V
  end.

ensure_dir(Path0) ->
  Path = ensure_list(Path0),
  ok = filelib:ensure_dir(Path),
  ok.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_bool(undefined, Default) -> Default;
to_bool(null, Default) -> Default;
to_bool(false, Default) -> Default;
to_bool(true, _Default) -> true;
to_bool(1, _Default) -> true;
to_bool(0, _Default) -> false;
to_bool(V, Default) ->
  S = string:lowercase(string:trim(to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.

rand_hex(Bytes) when is_integer(Bytes), Bytes > 0 ->
  _ = application:ensure_all_started(crypto),
  binary:encode_hex(crypto:strong_rand_bytes(Bytes), lowercase).
