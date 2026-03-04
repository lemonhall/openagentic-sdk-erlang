-module(openagentic_runtime).

-export([query/2]).

-define(DEFAULT_MAX_STEPS, 20).
-define(DEFAULT_TIMEOUT_MS, 60000).

query(Prompt0, Opts0) ->
  Prompt = iolist_to_binary(Prompt0),
  Opts = ensure_map(Opts0),

  RootDir = ensure_list(maps:get(session_root, Opts, openagentic_paths:default_session_root())),
  Metadata = maps:get(session_metadata, Opts, #{}),
  {ok, SessionId} = openagentic_session_store:create_session(RootDir, Metadata),

  Cwd = maps:get(cwd, Opts, ensure_list(file_get_cwd_safe())),
  ProjectDir = ensure_list(maps:get(project_dir, Opts, maps:get(projectDir, Opts, Cwd))),
  {ok, InitEv} = openagentic_session_store:append_event(RootDir, SessionId, openagentic_events:system_init(SessionId, Cwd, #{})),
  {ok, UserEv} = openagentic_session_store:append_event(RootDir, SessionId, openagentic_events:user_message(Prompt)),

  ApiKey = maps:get(api_key, Opts, maps:get(<<"api_key">>, Opts, undefined)),
  Model = maps:get(model, Opts, maps:get(<<"model">>, Opts, undefined)),
  BaseUrl = maps:get(base_url, Opts, maps:get(<<"base_url">>, Opts, undefined)),
  TimeoutMs = maps:get(timeout_ms, Opts, maps:get(<<"timeout_ms">>, Opts, ?DEFAULT_TIMEOUT_MS)),

  ProviderMod = maps:get(provider_mod, Opts, openagentic_openai_responses),
  ToolMods = maps:get(tools, Opts, default_tools()),
  ToolSchemas = openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir, directory => Cwd, cwd => Cwd}),
  Registry = openagentic_tool_registry:new(ToolMods),

  UserAnswerer = maps:get(user_answerer, Opts, undefined),
  PermissionGate = maps:get(permission_gate, Opts, openagentic_permissions:default(UserAnswerer)),
  AllowedTools = maps:get(allowed_tools, Opts, undefined),
  TaskRunner = maps:get(task_runner, Opts, undefined),
  MaxSteps = maps:get(max_steps, Opts, ?DEFAULT_MAX_STEPS),

  State0 = #{
    root => RootDir,
    session_id => SessionId,
    events => [InitEv, UserEv],
    project_dir => ProjectDir,
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    timeout_ms => TimeoutMs,
    provider_mod => ProviderMod,
    tool_schemas => ToolSchemas,
    registry => Registry,
    permission_gate => PermissionGate,
    allowed_tools => AllowedTools,
    user_answerer => UserAnswerer,
    task_runner => TaskRunner,
    previous_response_id => undefined,
    supports_previous_response_id => true,
    steps => 0,
    max_steps => MaxSteps
  },
  run_loop(State0).

run_loop(State0) ->
  Steps = maps:get(steps, State0),
  Max = maps:get(max_steps, State0),
  case Steps >= Max of
    true ->
      finalize_max_steps(State0);
    false ->
      case call_model(State0) of
        {ok, ModelOut, State1} ->
          handle_model_output(ModelOut, State1);
        {error, Reason, State1} ->
          finalize_error(State1, Reason)
      end
  end.

call_model(State0) ->
  Events = maps:get(events, State0, []),
  InputItems = openagentic_model_input:build_responses_input(Events),
  ProviderMod = maps:get(provider_mod, State0),
  ToolSchemas = maps:get(tool_schemas, State0, []),
  Opts = build_provider_opts(State0, InputItems, ToolSchemas),
  PrevId = maps:get(previous_response_id, State0, undefined),
  SupportsPrev = maps:get(supports_previous_response_id, State0, true),
  Opts2 =
    case {SupportsPrev, PrevId} of
      {true, undefined} -> Opts;
      {true, <<>>} -> Opts;
      {true, ""} -> Opts;
      {true, PrevVal} -> Opts#{previous_response_id => PrevVal};
      _ -> Opts
    end,
  case ProviderMod:complete(Opts2) of
    {ok, ModelOut} ->
      RespId = maps:get(response_id, ModelOut, undefined),
      State1 =
        case RespId of
          undefined -> State0;
          _ -> State0#{previous_response_id := RespId}
        end,
      {ok, ModelOut, bump_steps(State1)};
    {error, Reason} ->
      %% Kotlin-aligned fallback: if prev id breaks, retry without it once.
      Msg = string:lowercase(iolist_to_binary(io_lib:format("~p", [Reason]))),
      LooksPrev = (binary:match(Msg, <<"previous_response_id">>) =/= nomatch) orelse (binary:match(Msg, <<"previous response">>) =/= nomatch),
      case {SupportsPrev, PrevId, LooksPrev} of
        {true, PrevVal2, true} when PrevVal2 =/= undefined, PrevVal2 =/= <<>>, PrevVal2 =/= "" ->
          State1 = State0#{supports_previous_response_id := false},
          Opts3 = maps:remove(previous_response_id, Opts),
          case ProviderMod:complete(Opts3) of
            {ok, ModelOut2} ->
              RespId2 = maps:get(response_id, ModelOut2, undefined),
              State2 =
                case RespId2 of
                  undefined -> State1;
                  _ -> State1#{previous_response_id := RespId2}
                end,
              {ok, ModelOut2, bump_steps(State2)};
            {error, Reason2} ->
              {error, Reason2, bump_steps(State1)}
          end;
        _ ->
          {error, Reason, bump_steps(State0)}
      end
  end.

handle_model_output(ModelOut0, State0) ->
  ModelOut = ensure_map(ModelOut0),
  ToolCalls = maps:get(tool_calls, ModelOut, []),
  case ToolCalls of
    [] ->
      AssistantText = maps:get(assistant_text, ModelOut, <<>>),
      State1 =
        case AssistantText of
          <<>> -> State0;
          _ -> append_event(State0, openagentic_events:assistant_message(AssistantText))
        end,
      State2 = append_event(State1, openagentic_events:result(maps:get(response_id, ModelOut, <<>>), <<"end">>)),
      {ok, #{session_id => maps:get(session_id, State2), final_text => AssistantText}};
    _ ->
      State1 = lists:foldl(fun run_one_tool_call/2, State0, ToolCalls),
      run_loop(State1)
  end.

run_one_tool_call(ToolCall0, State0) ->
  ToolCall = ensure_map(ToolCall0),
  ToolUseId = maps:get(tool_use_id, ToolCall, maps:get(toolUseId, ToolCall, <<>>)),
  ToolName0 = maps:get(name, ToolCall, <<>>),
  ToolName = to_bin(ToolName0),
  ToolInput0 = maps:get(arguments, ToolCall, #{}),

  UseEv = openagentic_events:tool_use(ToolUseId, ToolName, ToolInput0),
  State1 = append_event(State0, UseEv),

  AllowedTools = maps:get(allowed_tools, State1, undefined),
  case is_tool_allowed(AllowedTools, ToolName) of
    false ->
      Msg = iolist_to_binary([<<"Tool '">>, ToolName, <<"' is not allowed">>]),
      append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"ToolNotAllowed">>, Msg));
    true ->
      Gate = maps:get(permission_gate, State1),
      Ctx = #{session_id => maps:get(session_id, State1), tool_use_id => ToolUseId},
      Approval = openagentic_permissions:approve(Gate, ToolName, ensure_map(ToolInput0), Ctx),
      State2 =
        case maps:get(question, Approval, undefined) of
          undefined -> State1;
          Q -> append_event(State1, Q)
        end,
      case maps:get(allowed, Approval, false) of
        false ->
          Deny = maps:get(deny_message, Approval, <<"tool use not approved">>),
          append_event(State2, openagentic_events:tool_result(ToolUseId, undefined, true, <<"PermissionDenied">>, Deny));
        true ->
          ToolInput = maps:get(updated_input, Approval, maps:get(updatedInput, Approval, ToolInput0)),
          case ToolName of
            <<"AskUserQuestion">> ->
              handle_ask_user_question(ToolUseId, ToolInput, State2);
            <<"Task">> ->
              handle_task(ToolUseId, ToolInput, State2);
            _ ->
              run_tool(ToolUseId, ToolName, ToolInput, State2)
          end
      end
  end.

run_tool(ToolUseId, ToolName0, ToolInput0, State0) ->
  ToolName = to_bin(ToolName0),
  ToolInput = ensure_map(ToolInput0),
  Registry = maps:get(registry, State0),
  ToolCtx =
    #{
      user_answerer => maps:get(user_answerer, State0, undefined),
      session_id => maps:get(session_id, State0, <<>>),
      tool_use_id => ToolUseId,
      task_runner => maps:get(task_runner, State0, undefined)
    },
  ProjectDir = maps:get(project_dir, State0, maps:get(projectDir, State0, ".")),
  ToolCtx2 = ToolCtx#{project_dir => ProjectDir},

  case openagentic_tool_registry:get(Registry, ToolName) of
    {ok, Mod} ->
      case Mod:run(ToolInput, ToolCtx2) of
        {ok, Out} ->
          append_event(State0, openagentic_events:tool_result(ToolUseId, Out, false, <<>>, <<>>));
        {error, {kotlin_error, ErrorType, ErrorMessage}} ->
          append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, ErrorType, ErrorMessage));
        {error, {exception, ErrorType, ErrorMessage}} ->
          append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, ErrorType, ErrorMessage));
        {error, Reason} ->
          append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"ToolError">>, to_bin(Reason)))
      end;
    {error, not_found} ->
      append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"UnknownTool">>, <<"unknown tool">>))
  end.

append_event(State0, Event0) ->
  Root = maps:get(root, State0),
  SessionId = maps:get(session_id, State0),
  {ok, Stored} = openagentic_session_store:append_event(Root, SessionId, Event0),
  Events0 = maps:get(events, State0, []),
  State0#{events := Events0 ++ [Stored]}.

finalize_error(State0, Reason) ->
  State1 = append_event(State0, openagentic_events:runtime_error(<<"runtime_error">>, Reason)),
  State2 = append_event(State1, openagentic_events:result(<<>>, <<"error">>)),
  {error, {runtime_error, Reason, maps:get(session_id, State2)}}.

finalize_max_steps(State0) ->
  State1 = append_event(State0, openagentic_events:result(maps:get(previous_response_id, State0, <<>>), <<"max_steps">>)),
  {ok, #{session_id => maps:get(session_id, State1), final_text => <<>>}}.

bump_steps(State0) ->
  Steps = maps:get(steps, State0, 0),
  State0#{steps := Steps + 1}.

build_provider_opts(State, InputItems, ToolSchemas) ->
  #{
    api_key => maps:get(api_key, State, <<"">>),
    model => maps:get(model, State, <<"">>),
    base_url => maps:get(base_url, State, undefined),
    timeout_ms => maps:get(timeout_ms, State, ?DEFAULT_TIMEOUT_MS),
    input => InputItems,
    tools => ToolSchemas
  }.

is_tool_allowed(undefined, _ToolName) ->
  true;
is_tool_allowed(Allowed, ToolName0) when is_list(Allowed) ->
  ToolName = to_bin(ToolName0),
  lists:member(ToolName, [to_bin(X) || X <- Allowed]);
is_tool_allowed(_Other, _ToolName) ->
  true.

default_tools() ->
  [
    openagentic_tool_ask_user_question,
    openagentic_tool_read,
    openagentic_tool_list,
    openagentic_tool_write,
    openagentic_tool_edit,
    openagentic_tool_glob,
    openagentic_tool_grep,
    openagentic_tool_bash,
    openagentic_tool_webfetch,
    openagentic_tool_websearch,
    openagentic_tool_skill,
    openagentic_tool_slash_command,
    openagentic_tool_notebook_edit,
    openagentic_tool_lsp,
    openagentic_tool_todo_write,
    openagentic_tool_task
  ].

file_get_cwd_safe() ->
  case file:get_cwd() of
    {ok, V} -> V;
    _ -> "."
  end.

handle_task(ToolUseId, ToolInput0, State0) ->
  ToolInput = ensure_map(ToolInput0),
  Agent = string:trim(to_bin(maps:get(<<"agent">>, ToolInput, maps:get(agent, ToolInput, <<>>)))),
  Prompt = string:trim(to_bin(maps:get(<<"prompt">>, ToolInput, maps:get(prompt, ToolInput, <<>>)))),
  case {byte_size(Agent) > 0, byte_size(Prompt) > 0} of
    {false, _} ->
      append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidTaskInput">>,
          <<"Task: 'agent' and 'prompt' must be non-empty strings">>
        )
      );
    {_, false} ->
      append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidTaskInput">>,
          <<"Task: 'agent' and 'prompt' must be non-empty strings">>
        )
      );
    {true, true} ->
      case maps:get(task_runner, State0, undefined) of
        F when is_function(F, 3) ->
          SessionId = maps:get(session_id, State0, <<>>),
          ToolCtx = #{session_id => SessionId, tool_use_id => ToolUseId},
          try
            Out = F(Agent, Prompt, ToolCtx),
            append_event(State0, openagentic_events:tool_result(ToolUseId, Out, false, <<>>, <<>>))
          catch
            C:R ->
              append_event(State0, openagentic_events:tool_result(ToolUseId, undefined, true, <<"TaskError">>, to_bin({C, R})))
          end;
        _ ->
          append_event(
            State0,
            openagentic_events:tool_result(
              ToolUseId,
              undefined,
              true,
              <<"NoTaskRunner">>,
              <<"Task: no taskRunner is configured">>
            )
          )
      end
  end.

handle_ask_user_question(ToolUseId0, ToolInput0, State0) ->
  ToolUseId = to_bin(ToolUseId0),
  ToolInput = ensure_map(ToolInput0),
  Questions = normalize_questions(ToolInput),
  case Questions of
    [] ->
      append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidAskUserQuestionInput">>,
          <<"AskUserQuestion: 'questions' must be a non-empty list">>
        )
      );
    _ ->
      case maps:get(user_answerer, State0, undefined) of
        F when is_function(F, 1) ->
          {State1, Answers} = ask_all_questions_loop(Questions, ToolUseId, 0, F, State0, #{}),
          Output = #{questions => Questions, answers => Answers},
          append_event(State1, openagentic_events:tool_result(ToolUseId, Output, false, <<>>, <<>>));
        _ ->
          append_event(
            State0,
            openagentic_events:tool_result(
              ToolUseId,
              undefined,
              true,
              <<"NoUserAnswerer">>,
              <<"AskUserQuestion: no userAnswerer is configured">>
            )
          )
      end
  end.

normalize_questions(Input) ->
  QuestionsEl = maps:get(<<"questions">>, Input, maps:get(questions, Input, undefined)),
  case QuestionsEl of
    M when is_map(M) -> [M];
    L when is_list(L) -> [ensure_map(X) || X <- L, is_map(X)];
    _ ->
      QText0 =
        first_non_empty(Input, [
          <<"question">>, question,
          <<"prompt">>, prompt
        ]),
      case QText0 of
        undefined ->
          [];
        _ ->
          QText = to_bin(QText0),
          OptsEl = maps:get(<<"options">>, Input, maps:get(options, Input, maps:get(<<"choices">>, Input, maps:get(choices, Input, undefined)))),
          Labels = parse_option_labels(OptsEl),
          Q = #{
            <<"question">> => QText,
            <<"options">> => [#{<<"label">> => Lbl} || Lbl <- Labels]
          },
          [Q]
      end
  end.

ask_all_questions_loop([], _ToolUseId, _I, _F, State0, Answers) ->
  {State0, Answers};
ask_all_questions_loop([Q0 | Rest], ToolUseId, I, F, State0, Answers0) ->
  Q = ensure_map(Q0),
  QText = string:trim(to_bin(maps:get(<<"question">>, Q, <<>>))),
  case byte_size(QText) > 0 of
    false ->
      ask_all_questions_loop(Rest, ToolUseId, I + 1, F, State0, Answers0);
    true ->
      Labels = parse_option_labels(maps:get(<<"options">>, Q, undefined)),
      Choices = case Labels of [] -> [<<"ok">>]; _ -> Labels end,
      Qid = iolist_to_binary([ToolUseId, <<":">>, integer_to_binary(I)]),
      Uq = openagentic_events:user_question(Qid, QText, Choices),
      State1 = append_event(State0, Uq),
      Ans = F(Uq),
      Answers1 = Answers0#{QText => Ans},
      ask_all_questions_loop(Rest, ToolUseId, I + 1, F, State1, Answers1)
  end.

parse_option_labels(undefined) -> [];
parse_option_labels(L) when is_list(L) ->
  lists:filtermap(
    fun (El0) ->
      case El0 of
        M when is_map(M) ->
          Lbl0 = first_non_empty(M, [<<"label">>, label, <<"name">>, name, <<"value">>, value]),
          case Lbl0 of
            undefined -> false;
            V ->
              S = string:trim(to_bin(V)),
              case byte_size(S) > 0 of true -> {true, S}; false -> false end
          end;
        _ ->
          S = string:trim(to_bin(El0)),
          case byte_size(S) > 0 of true -> {true, S}; false -> false end
      end
    end,
    L
  );
parse_option_labels(M) when is_map(M) ->
  parse_option_labels(maps:get(<<"options">>, M, maps:get(<<"choices">>, M, undefined)));
parse_option_labels(_) ->
  [].

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list({ok, V}) -> ensure_list(V);
ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
