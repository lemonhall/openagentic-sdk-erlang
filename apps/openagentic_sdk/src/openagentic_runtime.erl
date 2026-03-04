-module(openagentic_runtime).

-export([query/2]).

-define(DEFAULT_MAX_STEPS, 20).
-define(DEFAULT_TIMEOUT_MS, 60000).

query(Prompt0, Opts0) ->
  Prompt = iolist_to_binary(Prompt0),
  Opts = ensure_map(Opts0),

  RootDir = ensure_list(maps:get(session_root, Opts, openagentic_paths:default_session_root())),
  Metadata = maps:get(session_metadata, Opts, #{}),
  Resume0 =
    maps:get(
      resume_session_id,
      Opts,
      maps:get(resumeSessionId, Opts, maps:get(<<"resume_session_id">>, Opts, maps:get(<<"resumeSessionId">>, Opts, undefined)))
    ),
  Resume1 =
    case Resume0 of
      undefined -> <<>>;
      null -> <<>>;
      _ -> string:trim(to_bin(Resume0))
    end,
  %% Defensive: tolerate callers passing the atom 'undefined' as a resume id (common in Erlang options maps).
  Resume =
    case Resume1 of
      <<"undefined">> -> <<>>;
      _ -> Resume1
    end,

  Cwd = maps:get(cwd, Opts, ensure_list(file_get_cwd_safe())),
  ProjectDir = ensure_list(maps:get(project_dir, Opts, maps:get(projectDir, Opts, Cwd))),
  EventSink = maps:get(event_sink, Opts, maps:get(eventSink, Opts, undefined)),

  ApiKey = maps:get(api_key, Opts, maps:get(<<"api_key">>, Opts, undefined)),
  Model = maps:get(model, Opts, maps:get(<<"model">>, Opts, undefined)),
  BaseUrl = maps:get(base_url, Opts, maps:get(<<"base_url">>, Opts, undefined)),
  TimeoutMs = maps:get(timeout_ms, Opts, maps:get(<<"timeout_ms">>, Opts, ?DEFAULT_TIMEOUT_MS)),

  ProviderRetry = maps:get(provider_retry, Opts, maps:get(providerRetry, Opts, #{})),
  IncludePartial = maps:get(include_partial_messages, Opts, maps:get(includePartialMessages, Opts, false)),

  Protocol0 =
    maps:get(
      protocol,
      Opts,
      maps:get(
        provider_protocol,
        Opts,
        maps:get(
          providerProtocol,
          Opts,
          maps:get(
            provider_protocol_override,
            Opts,
            maps:get(providerProtocolOverride, Opts, maps:get(<<"protocol">>, Opts, maps:get(<<"provider_protocol">>, Opts, maps:get(<<"providerProtocol">>, Opts, undefined))))
          )
        )
      )
    ),
  Protocol = openagentic_provider_protocol:normalize(Protocol0),

  ProviderMod =
    case maps:get(provider_mod, Opts, undefined) of
      undefined ->
        case Protocol of
          legacy -> openagentic_openai_chat_completions;
          responses -> openagentic_openai_responses
        end;
      M -> M
    end,

  SystemPrompt0 =
    maps:get(
      system_prompt,
      Opts,
      maps:get(systemPrompt, Opts, maps:get(<<"system_prompt">>, Opts, maps:get(<<"systemPrompt">>, Opts, undefined)))
    ),
  SystemPrompt1 = string:trim(to_bin(SystemPrompt0)),
  SystemPrompt = case SystemPrompt1 of <<>> -> undefined; <<"undefined">> -> undefined; _ -> SystemPrompt1 end,

  TaskAgents = maps:get(task_agents, Opts, maps:get(taskAgents, Opts, [])),
  AgentsVar = openagentic_task_agents:render_agents_for_prompt(TaskAgents),

  ToolMods = maps:get(tools, Opts, default_tools()),
  ToolSchemas =
    openagentic_tool_schemas:responses_tools(ToolMods, #{project_dir => ProjectDir, directory => Cwd, cwd => Cwd, agents => AgentsVar}),
  Registry = openagentic_tool_registry:new(ToolMods),

  UserAnswerer = maps:get(user_answerer, Opts, undefined),
  PermissionGate = maps:get(permission_gate, Opts, openagentic_permissions:default(UserAnswerer)),
  AllowedTools = maps:get(allowed_tools, Opts, undefined),
  TaskProgressEmitter = maps:get(task_progress_emitter, Opts, maps:get(taskProgressEmitter, Opts, undefined)),
  TaskRunner0 = maps:get(task_runner, Opts, undefined),
  HookEngine = maps:get(hook_engine, Opts, maps:get(hookEngine, Opts, #{})),
  ToolOutputArtifacts = maps:get(tool_output_artifacts, Opts, maps:get(toolOutputArtifacts, Opts, #{})),
  MaxSteps = maps:get(max_steps, Opts, ?DEFAULT_MAX_STEPS),
  ResumeMaxEvents = maps:get(resume_max_events, Opts, maps:get(resumeMaxEvents, Opts, 1000)),
  ResumeMaxBytes = maps:get(resume_max_bytes, Opts, maps:get(resumeMaxBytes, Opts, 2000000)),
  TaskRunner =
    case {TaskRunner0, openagentic_task_agents:has_agent(<<"explore">>, TaskAgents)} of
      {undefined, true} -> openagentic_task_runners:built_in_explore(Opts);
      _ -> TaskRunner0
    end,

  SupportsPrevDefault = case Protocol of legacy -> false; responses -> true end,
  SupportsPrev0 = maps:get(supports_previous_response_id, Opts, maps:get(supportsPreviousResponseId, Opts, SupportsPrevDefault)),
  SupportsPrev = case SupportsPrev0 of true -> true; false -> false; _ -> SupportsPrevDefault end,
  CompactionCfg = ensure_map(maps:get(compaction, Opts, maps:get(<<"compaction">>, Opts, #{}))),

  ResumeRes =
    case byte_size(Resume) > 0 of
      true ->
        try
          _ = openagentic_session_store:session_dir(RootDir, Resume),
          Past0 = openagentic_session_store:read_events(RootDir, Resume),
          Past = trim_events_for_resume(Past0, ResumeMaxEvents, ResumeMaxBytes),
          Prev = infer_previous_response_id(Past),
          {ok, {Resume, Past, Prev}}
        catch
          _:_ -> {error, {invalid_session_id, Resume}}
        end;
      false ->
        {ok, Sid} = openagentic_session_store:create_session(RootDir, Metadata),
        {ok, {Sid, [], undefined}}
    end,
  case ResumeRes of
    {error, Reason} ->
      {error, Reason};
    {ok, {SessionId, PastEvents, PrevRespId}} ->
      State0 = #{
        root => RootDir,
        session_id => SessionId,
        events => PastEvents,
        event_sink => EventSink,
        project_dir => ProjectDir,
        api_key => ApiKey,
        model => Model,
        base_url => BaseUrl,
        timeout_ms => TimeoutMs,
        provider_mod => ProviderMod,
        provider_retry => ProviderRetry,
        include_partial_messages => IncludePartial,
        resume_max_events => ResumeMaxEvents,
        resume_max_bytes => ResumeMaxBytes,
        compaction => CompactionCfg,
        protocol => Protocol,
        system_prompt => SystemPrompt,
        tool_schemas => ToolSchemas,
        registry => Registry,
        permission_gate => PermissionGate,
        allowed_tools => AllowedTools,
        user_answerer => UserAnswerer,
        task_progress_emitter => TaskProgressEmitter,
        task_runner => TaskRunner,
        hook_engine => HookEngine,
        tool_output_artifacts => ToolOutputArtifacts,
        task_agents => TaskAgents,
        previous_response_id => PrevRespId,
        supports_previous_response_id => SupportsPrev,
        steps => 0,
        max_steps => MaxSteps
      },
      State1 =
        case byte_size(Resume) > 0 of
          true -> State0;
          false -> append_event(State0, openagentic_events:system_init(SessionId, Cwd, #{}))
        end,
      State2 = append_event(State1, openagentic_events:user_message(Prompt)),
      run_loop(State2)
  end.

trim_events_for_resume(Events0, MaxEvents0, MaxBytes0) ->
  Events = ensure_list(Events0),
  MaxEvents = erlang:max(0, MaxEvents0),
  MaxBytes = erlang:max(0, MaxBytes0),
  case {MaxEvents =< 0, MaxBytes =< 0} of
    {true, true} ->
      Events;
    _ ->
      trim_events_for_resume_loop(lists:reverse(Events), MaxEvents, MaxBytes, [], 0)
  end.

trim_events_for_resume_loop([], _MaxEvents, _MaxBytes, Acc, _Bytes) ->
  lists:reverse(Acc);
trim_events_for_resume_loop([E | Rest], MaxEvents, MaxBytes, Acc0, Bytes0) ->
  case (MaxEvents > 0 andalso length(Acc0) >= MaxEvents) of
    true -> lists:reverse(Acc0);
    false ->
      Approx = safe_event_len(E),
      case (MaxBytes > 0 andalso (Bytes0 + Approx) > MaxBytes andalso Acc0 =/= []) of
        true ->
          lists:reverse(Acc0);
        false ->
          trim_events_for_resume_loop(Rest, MaxEvents, MaxBytes, [E | Acc0], Bytes0 + Approx)
      end
  end.

safe_event_len(E) ->
  try
    byte_size(openagentic_json:encode(ensure_map(E)))
  catch
    _:_ -> 0
  end.

infer_previous_response_id(Events0) ->
  Events = ensure_list(Events0),
  infer_previous_response_id_loop(lists:reverse(Events)).

infer_previous_response_id_loop([]) ->
  undefined;
infer_previous_response_id_loop([E0 | Rest]) ->
  E = ensure_map(E0),
  Type = to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  case Type of
    <<"result">> ->
      Resp0 = maps:get(<<"response_id">>, E, maps:get(response_id, E, undefined)),
      Resp = string:trim(to_bin(Resp0)),
      case byte_size(Resp) > 0 of
        true -> Resp;
        false -> infer_previous_response_id_loop(Rest)
      end;
    _ -> infer_previous_response_id_loop(Rest)
  end.

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
  InputItems0 = openagentic_model_input:build_responses_input(Events),
  InputItems = maybe_prepend_system_prompt(State0, InputItems0),
  ProviderMod = maps:get(provider_mod, State0),
  ToolSchemas = maps:get(tool_schemas, State0, []),
  Opts = build_provider_opts(State0, InputItems, ToolSchemas),
  RetryCfg = maps:get(provider_retry, State0, #{}),
  OptsD =
    case maps:get(include_partial_messages, State0, false) of
      true ->
        Sink = fun (DeltaBin) -> emit_transient_event(State0, openagentic_events:assistant_delta(DeltaBin)) end,
        Opts#{on_delta => Sink};
      false ->
        Opts
    end,
  PrevId = maps:get(previous_response_id, State0, undefined),
  SupportsPrev = maps:get(supports_previous_response_id, State0, true),
  Protocol = maps:get(protocol, State0, responses),
  Opts2 =
    case {Protocol, SupportsPrev, PrevId} of
      {responses, true, undefined} -> OptsD;
      {responses, true, <<>>} -> OptsD;
      {responses, true, ""} -> OptsD;
      {responses, true, PrevVal} -> OptsD#{previous_response_id => PrevVal};
      _ -> OptsD
    end,
  case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Opts2) end, RetryCfg) of
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
      case {Protocol, SupportsPrev, PrevId, LooksPrev} of
        {responses, true, PrevVal2, true} when PrevVal2 =/= undefined, PrevVal2 =/= <<>>, PrevVal2 =/= "" ->
          State1 = State0#{supports_previous_response_id := false},
          Opts3 = maps:remove(previous_response_id, OptsD),
          case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Opts3) end, RetryCfg) of
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
      %% Kotlin parity: after tool loop, optionally run compaction on overflow (eligible when we can't rely on previous_response_id).
      case maybe_run_compaction_overflow(ModelOut, State1) of
        {compacted, StateC} ->
          run_loop(StateC);
         {no_compaction, StateNC} ->
      Usage0 = maps:get(usage, ModelOut, undefined),
      Usage =
        case Usage0 of
          null -> undefined;
          U when is_map(U) -> U;
          _ -> undefined
        end,
      ResponseId0 = maps:get(previous_response_id, StateNC, undefined),
      ResponseId1 = string:trim(to_bin(ResponseId0)),
      ResponseId =
        case ResponseId1 of
          <<>> -> undefined;
          <<"undefined">> -> undefined;
          _ -> ResponseId1
        end,
      Steps = maps:get(steps, State1, 0),
      Sid = maps:get(session_id, State1, <<>>),
      State2 =
        append_event(
          StateNC,
          openagentic_events:result(
            AssistantText,
            Sid,
            <<"end">>,
            Usage,
            ResponseId,
            undefined,
            Steps
          )
        ),
      {ok, #{session_id => maps:get(session_id, State2), final_text => AssistantText}}
      end;
    _ ->
      State1 = lists:foldl(fun run_one_tool_call/2, State0, ToolCalls),
      State2 = maybe_prune_tool_outputs(State1),
      run_loop(State2)
  end.

maybe_prune_tool_outputs(State0) ->
  Compaction = ensure_map(maps:get(compaction, State0, #{})),
  Prune = maps:get(prune, Compaction, maps:get(<<"prune">>, Compaction, true)),
  case Prune of
    false ->
      State0;
    _ ->
      Ids = openagentic_compaction:select_tool_outputs_to_prune(maps:get(events, State0, []), Compaction),
      case Ids of
        [] -> State0;
        _ ->
          Now = erlang:system_time(millisecond) / 1000.0,
          lists:foldl(
            fun (Tid0, Acc) ->
              Tid = to_bin(Tid0),
              append_event(Acc, openagentic_events:tool_output_compacted(Tid, Now))
            end,
            State0,
            Ids
          )
      end
  end.

maybe_run_compaction_overflow(ModelOut, State0) ->
  Compaction = ensure_map(maps:get(compaction, State0, #{})),
  Auto = maps:get(auto, Compaction, maps:get(<<"auto">>, Compaction, true)),
  SupportsPrev = maps:get(supports_previous_response_id, State0, true),
  Protocol = maps:get(protocol, State0, responses),
  %% Kotlin parity: overflow compaction is eligible for legacy, or for responses providers that can't rely on previous_response_id.
  Eligible = (Auto =:= true) andalso ((Protocol =:= legacy) orelse (SupportsPrev =:= false)),
  Usage = maps:get(usage, ensure_map(ModelOut), undefined),
  case Eligible andalso openagentic_compaction:would_overflow(Compaction, ensure_map(Usage)) of
    true ->
      State1 = append_event(State0, openagentic_events:user_compaction(true, <<"overflow">>)),
      State2 = run_compaction_pass(State1),
      {compacted, State2#{previous_response_id := undefined}};
    false ->
      {no_compaction, State0}
  end.

run_compaction_pass(State0) ->
  Root = maps:get(root, State0),
  Sid0 = maps:get(session_id, State0, <<>>),
  Sid = to_bin(Sid0),
  ResumeMaxEvents = maps:get(resume_max_events, State0, 1000),
  ResumeMaxBytes = maps:get(resume_max_bytes, State0, 2000000),
  Events0 = openagentic_session_store:read_events(Root, Sid),
  History =
    openagentic_compaction:build_compaction_transcript(
      Events0,
      ResumeMaxEvents,
      ResumeMaxBytes,
      openagentic_compaction:tool_output_placeholder()
    ),
  InputItems =
    [#{role => <<"system">>, content => openagentic_compaction:compaction_system_prompt()}] ++
      History ++
      [#{role => <<"user">>, content => openagentic_compaction:compaction_user_instruction()}],
  ProviderMod = maps:get(provider_mod, State0),
  RetryCfg = maps:get(provider_retry, State0, #{}),
  Req0 = build_provider_opts(State0, InputItems, []),
  Req = Req0#{store => false},
  case openagentic_provider_retry:call(fun () -> ProviderMod:complete(Req) end, RetryCfg) of
    {ok, ModelOut} ->
      Summary = maps:get(assistant_text, ensure_map(ModelOut), <<>>),
      case byte_size(string:trim(to_bin(Summary))) > 0 of
        true -> append_event(State0, openagentic_events:assistant_message(Summary, true));
        false -> State0
      end;
    {error, Reason} ->
      %% Best-effort: record error and continue without compaction.
      append_event(State0, openagentic_events:runtime_error(<<"compaction">>, <<"CompactionError">>, to_bin(Reason), to_bin(ProviderMod), undefined))
  end.

run_one_tool_call(ToolCall0, State0) ->
  ToolCall = ensure_map(ToolCall0),
  ToolUseId = maps:get(tool_use_id, ToolCall, maps:get(toolUseId, ToolCall, <<>>)),
  ToolName0 = maps:get(name, ToolCall, <<>>),
  ToolName = to_bin(ToolName0),
  ToolInput0 = ensure_map(maps:get(arguments, ToolCall, #{})),

  HookCtx = #{session_id => maps:get(session_id, State0), tool_use_id => ToolUseId},
  HookEngine = maps:get(hook_engine, State0, #{}),
  Pre = openagentic_hook_engine:run_pre_tool_use(HookEngine, ToolName, ToolInput0, HookCtx),
  StateH = append_hook_events(State0, maps:get(events, Pre, [])),
  ToolInput1 = ensure_map(maps:get(input, Pre, ToolInput0)),

  UseEv = openagentic_events:tool_use(ToolUseId, ToolName, ToolInput1),
  State1 = append_event(StateH, UseEv),

  case maps:get(decision, Pre, undefined) of
    D when is_map(D) ->
      case maps:get(block, D, false) of
        true ->
          Reason = maps:get(block_reason, D, <<"blocked by hook">>),
          append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"HookBlocked">>, Reason));
        false ->
          run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1)
      end;
    _ ->
      run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1)
  end.

run_one_tool_call_allowed(ToolUseId, ToolName, ToolInput1, HookCtx, State1) ->
  AllowedTools = maps:get(allowed_tools, State1, undefined),
  case is_tool_allowed(AllowedTools, ToolName) of
    false ->
      Msg = iolist_to_binary([<<"Tool '">>, ToolName, <<"' is not allowed">>]),
      append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"ToolNotAllowed">>, Msg));
    true ->
      Gate = maps:get(permission_gate, State1),
      Ctx = #{session_id => maps:get(session_id, State1), tool_use_id => ToolUseId},
      Approval = openagentic_permissions:approve(Gate, ToolName, ToolInput1, Ctx),
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
          ToolInput = maps:get(updated_input, Approval, maps:get(updatedInput, Approval, ToolInput1)),
          case ToolName of
            <<"AskUserQuestion">> ->
              handle_ask_user_question(ToolUseId, ToolName, ToolInput, HookCtx, State2);
            <<"Task">> ->
              handle_task(ToolUseId, ToolName, ToolInput, HookCtx, State2);
            _ ->
              run_tool(ToolUseId, ToolName, ToolInput, HookCtx, State2)
          end
      end
  end
  .

run_tool(ToolUseId, ToolName0, ToolInput0, HookCtx, State0) ->
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
          finish_tool_success(ToolUseId, ToolName, Out, HookCtx, State0);
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
  _ = maybe_emit_event(State0, Stored),
  Events0 = maps:get(events, State0, []),
  State0#{events := Events0 ++ [Stored]}.

maybe_emit_event(State0, Event) ->
  case maps:get(event_sink, State0, undefined) of
    F when is_function(F, 1) ->
      try
        F(Event)
      catch
        _:_ -> ok
      end;
    _ -> ok
  end.

emit_transient_event(State0, Event) ->
  %% Transient events are not persisted and do not affect session history.
  _ = maybe_emit_event(State0, Event),
  ok.

append_hook_events(State0, Events0) ->
  Events = ensure_list(Events0),
  lists:foldl(fun (E, Acc) -> append_event(Acc, E) end, State0, Events).

finish_tool_success(ToolUseId0, ToolName0, Out0, HookCtx0, State0) ->
  ToolUseId = to_bin(ToolUseId0),
  ToolName = to_bin(ToolName0),
  HookCtx = ensure_map(HookCtx0),
  HookEngine = maps:get(hook_engine, State0, #{}),
  Post = openagentic_hook_engine:run_post_tool_use(HookEngine, ToolName, Out0, HookCtx),
  State1 = append_hook_events(State0, maps:get(events, Post, [])),
  case maps:get(decision, Post, undefined) of
    D when is_map(D) ->
      case maps:get(block, D, false) of
        true ->
          Reason = maps:get(block_reason, D, <<"blocked by hook">>),
          append_event(State1, openagentic_events:tool_result(ToolUseId, undefined, true, <<"HookBlocked">>, Reason));
        false ->
          Out1 = maps:get(output, Post, Out0),
          Out2 = maybe_externalize_tool_output(ToolUseId, ToolName, Out1, State1),
          append_event(State1, openagentic_events:tool_result(ToolUseId, Out2, false, <<>>, <<>>))
      end;
    _ ->
      Out1 = maps:get(output, Post, Out0),
      Out2 = maybe_externalize_tool_output(ToolUseId, ToolName, Out1, State1),
      append_event(State1, openagentic_events:tool_result(ToolUseId, Out2, false, <<>>, <<>>))
  end.

maybe_externalize_tool_output(ToolUseId0, ToolName0, Output0, State0) ->
  Cfg0 = ensure_map(maps:get(tool_output_artifacts, State0, #{})),
  Enabled = maps:get(enabled, Cfg0, maps:get(<<"enabled">>, Cfg0, true)),
  case Enabled of
    false ->
      Output0;
    _ ->
      case Output0 of
        undefined -> Output0;
        null -> Output0;
        _ ->
          Encoded =
            try
              openagentic_json:encode(Output0)
            catch
              _:_ -> undefined
            end,
          case Encoded of
            undefined ->
              Output0;
            _ ->
              MaxBytes = int_default(Cfg0, [max_bytes, <<"max_bytes">>], 51200),
              case byte_size(Encoded) =< MaxBytes of
                true ->
                  Output0;
                false ->
                  DirName = ensure_list(maps:get(dir_name, Cfg0, maps:get(dirName, Cfg0, "tool-output"))),
                  Root = ensure_list(maps:get(root, State0)),
                  Dir = filename:join([Root, DirName]),
                  PreviewMax = int_default(Cfg0, [preview_max_chars, <<"preview_max_chars">>], 2500),
                  SessionId = to_bin(maps:get(session_id, State0)),
                  ToolUseId = to_bin(ToolUseId0),
                  ToolName = to_bin(ToolName0),
                  OriginalChars = string:length(bin_to_list_safe(Encoded)),
                  Preview = head_tail_truncate(Encoded, PreviewMax),
                  ArtifactPath = write_tool_output_artifact(Dir, ToolUseId, ToolName, Encoded),
                  Hint = build_truncation_hint(ArtifactPath, State0),
                  Wrapper0 = #{
                    '_openagentic_truncated' => true,
                    reason => <<"tool_output_too_large">>,
                    session_id => SessionId,
                    tool_use_id => ToolUseId,
                    tool_name => ToolName,
                    original_chars => OriginalChars,
                    preview => Preview,
                    hint => Hint
                  },
                  case ArtifactPath of
                    undefined -> Wrapper0;
                    _ -> Wrapper0#{artifact_path => openagentic_fs:norm_abs_bin(ArtifactPath)}
                  end
              end
          end
      end
  end.

write_tool_output_artifact(Dir0, ToolUseId0, ToolName0, Encoded) ->
  Dir = ensure_list(Dir0),
  ToolUseId = ensure_list(ToolUseId0),
  ToolName = ensure_list(ToolName0),
  case filelib:ensure_dir(filename:join([Dir, "x"])) of
    ok ->
      FileName = build_tool_output_filename(ToolUseId, ToolName),
      Path = filename:join([Dir, FileName]),
      case file:write_file(Path, Encoded) of
        ok -> Path;
        _ -> undefined
      end;
    _ ->
      undefined
  end.

build_tool_output_filename(ToolUseId0, ToolName0) ->
  Id = safe_piece(ToolUseId0),
  Name = safe_piece(ToolName0),
  lists:flatten(["tool_", Id, "_", Name, ".json"]).

safe_piece(S0) ->
  S1 = string:trim(ensure_list(S0)),
  S = case S1 of "" -> "x"; _ -> S1 end,
  Out0 = [safe_char(C) || C <- S],
  Out = lists:sublist(Out0, 120),
  case Out of [] -> "x"; _ -> Out end.

safe_char(C) when C >= $a, C =< $z -> C;
safe_char(C) when C >= $A, C =< $Z -> C;
safe_char(C) when C >= $0, C =< $9 -> C;
safe_char($_) -> $_;
safe_char($-) -> $-;
safe_char($.) -> $.;
safe_char(_) -> $_.

build_truncation_hint(ArtifactPath0, State0) ->
  Saved =
    case ArtifactPath0 of
      undefined -> <<"(unavailable)">>;
      "" -> <<"(unavailable)">>;
      <<>> -> <<"(unavailable)">>;
      P -> to_bin(P)
    end,
  TaskRunner = maps:get(task_runner, State0, undefined),
  AllowedTools = maps:get(allowed_tools, State0, undefined),
  TaskAllowed = (TaskRunner =/= undefined) andalso is_tool_allowed(AllowedTools, <<"Task">>),
  TaskAgents0 = maps:get(task_agents, State0, []),
  TaskAgents = [to_bin(A) || A <- ensure_list(TaskAgents0)],
  HasExplore = lists:any(fun (A) -> A =:= <<"explore">> end, TaskAgents),
  case TaskAllowed andalso HasExplore of
    true ->
      iolist_to_binary(lists:join(<<"\n">>, [
        <<"The tool call succeeded but the output was truncated.">>,
        iolist_to_binary([<<"Full output saved to: ">>, Saved]),
        <<"Next: Use Task(agent=\"explore\") to grep/read only relevant parts (offset/limit). Do NOT read the full file yourself.">>
      ]));
    false ->
      iolist_to_binary(lists:join(<<"\n">>, [
        <<"The tool call succeeded but the output was truncated.">>,
        iolist_to_binary([<<"Full output saved to: ">>, Saved]),
        <<"Next: Use Grep to search and Read with offset/limit to view specific sections (avoid reading the full file).">>
      ]))
  end.

head_tail_truncate(Text0, MaxChars0) ->
  Limit = erlang:max(0, MaxChars0),
  case Limit =< 0 of
    true -> <<>>;
    false ->
      TextList = bin_to_list_safe(Text0),
      case length(TextList) =< Limit of
        true -> unicode:characters_to_binary(TextList, utf8);
        false ->
          Truncated = head_tail_truncate_loop(TextList, Limit),
          unicode:characters_to_binary(Truncated, utf8)
      end
  end.

head_tail_truncate_loop(TextList, Limit) ->
  Len = length(TextList),
  Removed0 = erlang:max(0, Len - Limit),
  Marker0 = marker(Removed0),
  head_tail_truncate_loop2(TextList, Limit, Marker0, 0).

head_tail_truncate_loop2(TextList, Limit, Marker, Iter) when Iter >= 3 ->
  head_tail_truncate_build(TextList, Limit, Marker);
head_tail_truncate_loop2(TextList, Limit, Marker, Iter) ->
  Remaining = erlang:max(0, Limit - length(Marker)),
  case Remaining =< 0 of
    true ->
      lists:sublist(Marker, Limit);
    false ->
      HeadLen = Remaining div 2,
      TailLen = Remaining - HeadLen,
      Len = length(TextList),
      Removed = erlang:max(0, Len - HeadLen - TailLen),
      Marker2 = marker(Removed),
      case length(Marker2) =:= length(Marker) of
        true ->
          head_tail_truncate_build(TextList, Limit, Marker2);
        false ->
          head_tail_truncate_loop2(TextList, Limit, Marker2, Iter + 1)
      end
  end.

head_tail_truncate_build(TextList, Limit, Marker) ->
  Remaining = erlang:max(0, Limit - length(Marker)),
  case Remaining =< 0 of
    true ->
      lists:sublist(Marker, Limit);
    false ->
      HeadLen = Remaining div 2,
      TailLen = Remaining - HeadLen,
      Head = lists:sublist(TextList, HeadLen),
      Tail = lists:nthtail(length(TextList) - TailLen, TextList),
      Head ++ Marker ++ Tail
  end.

marker(Removed) ->
  lists:flatten(io_lib:format("\n…~p chars truncated…\n", [Removed])).

bin_to_list_safe(Bin) when is_binary(Bin) ->
  try
    unicode:characters_to_list(Bin, utf8)
  catch
    _:_ -> binary_to_list(Bin)
  end;
bin_to_list_safe(Other) ->
  ensure_list(Other).

int_default(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.

finalize_error(State0, Reason) ->
  Sid = maps:get(session_id, State0, <<>>),
  Steps = maps:get(steps, State0, 0),
  Provider = maps:get(provider_mod, State0, undefined),
  Phase = error_phase(Reason),
  ErrMsg = truncate_bin(to_bin(Reason), 2000),
  ErrType = error_type(Reason),
  State1 = append_event(State0, openagentic_events:runtime_error(Phase, ErrType, ErrMsg, to_bin(Provider), undefined)),
  State2 =
    append_event(
      State1,
      openagentic_events:result(
        <<>>,
        Sid,
        <<"error">>,
        undefined,
        maps:get(previous_response_id, State0, undefined),
        undefined,
        Steps
      )
    ),
  {error, {runtime_error, Reason, maps:get(session_id, State2)}}.

finalize_max_steps(State0) ->
  Sid = maps:get(session_id, State0, <<>>),
  Steps = maps:get(steps, State0, 0),
  RespId = maps:get(previous_response_id, State0, undefined),
  State1 =
    append_event(
      State0,
      openagentic_events:result(
        <<>>,
        Sid,
        <<"max_steps">>,
        undefined,
        RespId,
        undefined,
        Steps
      )
    ),
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

handle_task(ToolUseId, ToolName0, ToolInput0, HookCtx, State0) ->
  ToolName = to_bin(ToolName0),
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
          Emit = maps:get(task_progress_emitter, State0, undefined),
          ToolCtx =
            case Emit of
              Ef when is_function(Ef, 1) -> #{session_id => SessionId, tool_use_id => ToolUseId, emit_progress => Ef};
              _ -> #{session_id => SessionId, tool_use_id => ToolUseId}
            end,
          try
            Out = F(Agent, Prompt, ToolCtx),
            finish_tool_success(ToolUseId, ToolName, Out, HookCtx, State0)
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

handle_ask_user_question(ToolUseId0, ToolName0, ToolInput0, HookCtx, State0) ->
  ToolUseId = to_bin(ToolUseId0),
  ToolName = to_bin(ToolName0),
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
          finish_tool_success(ToolUseId, ToolName, Output, HookCtx, State1);
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

%% ---- provider input helpers ----

maybe_prepend_system_prompt(State0, InputItems0) ->
  InputItems = ensure_list(InputItems0),
  case maps:get(system_prompt, State0, undefined) of
    P when is_binary(P) ->
      P2 = string:trim(P),
      case byte_size(P2) > 0 of
        true -> [#{role => <<"system">>, content => P2} | InputItems];
        false -> InputItems
      end;
    _ ->
      InputItems
  end.

%% ---- error helpers ----

error_phase(Reason) ->
  case is_provider_error(Reason) of
    true -> <<"provider">>;
    false -> <<"session">>
  end.

error_type(Reason) ->
  case is_provider_error(Reason) of
    true -> <<"ProviderError">>;
    false -> <<"RuntimeError">>
  end.

is_provider_error({http_error, _Status, _Headers, _Body}) -> true;
is_provider_error({httpc_request_failed, _}) -> true;
is_provider_error({httpc_set_options_failed, _}) -> true;
is_provider_error({invalid_proxy, _}) -> true;
is_provider_error({missing_required, _}) -> true;
is_provider_error({missing, _}) -> true;
is_provider_error(_) -> false.

truncate_bin(Bin0, MaxChars0) ->
  Bin = to_bin(Bin0),
  MaxChars = erlang:max(0, MaxChars0),
  case MaxChars =< 0 of
    true ->
      <<>>;
    false ->
      try
        L = unicode:characters_to_list(Bin, utf8),
        case length(L) =< MaxChars of
          true -> unicode:characters_to_binary(L, utf8);
          false -> unicode:characters_to_binary(lists:sublist(L, MaxChars), utf8)
        end
      catch
        _:_ ->
          %% Best-effort: fall back to bytes.
          case byte_size(Bin) =< MaxChars of
            true -> Bin;
            false -> binary:part(Bin, 0, MaxChars)
          end
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
