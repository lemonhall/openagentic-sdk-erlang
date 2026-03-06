-module(openagentic_workflow_engine).

-export([run/4, start/4, continue/4, continue_start/4]).

-define(DEFAULT_MAX_STEPS, 50).

%% Synchronous, local-first workflow runner.
%%
%% - Loads + validates workflow DSL (JSON)
%% - Creates a workflow session for workflow.* events
%% - Runs steps sequentially (each step gets its own session)
%% - Enforces output contracts + deterministic guards
%%
%% Future: wrap in OTP (manager + gen_statem) for async start/status/cancel.

run(ProjectDir0, WorkflowRelPath0, ControllerInput0, Opts0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  WorkflowRelPath = ensure_list_str(WorkflowRelPath0),
  ControllerInput = to_bin(ControllerInput0),
  Opts = ensure_map(Opts0),
  SessionRoot = ensure_list_str(maps:get(session_root, Opts, openagentic_paths:default_session_root())),

  case init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) of
    {ok, Start, State0} ->
      execute(Start, State0);
    Err ->
      Err
  end.

%% Start a workflow asynchronously (returns ids immediately).
%% The workflow continues in a spawned process and writes events to workflow session.
start(ProjectDir0, WorkflowRelPath0, ControllerInput0, Opts0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  WorkflowRelPath = ensure_list_str(WorkflowRelPath0),
  ControllerInput = to_bin(ControllerInput0),
  Opts = ensure_map(Opts0),
  SessionRoot = ensure_list_str(maps:get(session_root, Opts, openagentic_paths:default_session_root())),
  case init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) of
    {ok, Start, State0} ->
      Pid =
        spawn(
          fun () ->
            _ = execute(Start, State0),
            ok
          end
        ),
      {ok, #{
        pid => Pid,
        workflow_id => wf_id(State0),
        workflow_name => maps:get(workflow_name, State0, <<>>),
        workflow_session_id => to_bin(maps:get(workflow_session_id, State0, <<>>))
      }};
    Err ->
      Err
  end.

%% Continue an existing workflow session by re-running (sync) from the last relevant step.
%% Keeps the same workflow_session_id and appends events to it.
continue(SessionRoot0, WorkflowSessionId0, Message0, Opts0) ->
  SessionRoot = ensure_list_str(SessionRoot0),
  WorkflowSessionId = ensure_list_str(WorkflowSessionId0),
  Message = to_bin(Message0),
  Opts = ensure_map(Opts0),
  case init_continue(SessionRoot, WorkflowSessionId, Message, Opts) of
    {ok, StartStepId, State0} ->
      execute(StartStepId, State0);
    Err ->
      Err
  end.

%% Continue an existing workflow session asynchronously.
continue_start(SessionRoot0, WorkflowSessionId0, Message0, Opts0) ->
  SessionRoot = ensure_list_str(SessionRoot0),
  WorkflowSessionId = ensure_list_str(WorkflowSessionId0),
  Message = to_bin(Message0),
  Opts = ensure_map(Opts0),
  case init_continue(SessionRoot, WorkflowSessionId, Message, Opts) of
    {ok, StartStepId, State0} ->
      Pid =
        spawn(
          fun () ->
            _ = execute(StartStepId, State0),
            ok
          end
        ),
      {ok, #{
        pid => Pid,
        workflow_id => wf_id(State0),
        workflow_name => maps:get(workflow_name, State0, <<>>),
        workflow_session_id => to_bin(maps:get(workflow_session_id, State0, <<>>))
      }};
    Err ->
      Err
  end.

init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) ->
  TimeContext = openagentic_time_context:resolve(Opts),
  Opts1 = openagentic_time_context:put_in_opts(Opts, TimeContext),
  case openagentic_workflow_dsl:load_and_validate(ProjectDir, WorkflowRelPath, Opts1) of
    {ok, Wf} ->
      case read_workflow_source(ProjectDir, WorkflowRelPath) of
        {ok, SrcBin} ->
          DslHash = sha256_hex(SrcBin),
          WfName = maps:get(<<"name">>, Wf, <<>>),
          WorkflowId = new_id(),
          {ok, WfSessionId0} =
            openagentic_session_store:create_session(SessionRoot, #{
              workflow_id => WorkflowId,
              workflow_name => WfName,
              dsl_path => to_bin(WorkflowRelPath),
              dsl_sha256 => DslHash,
              time_context => TimeContext
            }),
           WfSessionId = to_bin(WfSessionId0),
           Opts2 = ensure_web_answerer(Opts1, WfSessionId),
           WfWorkspaceDir = workflow_workspace_dir(SessionRoot, WfSessionId0),
           ok = filelib:ensure_dir(filename:join([WfWorkspaceDir, "x"])),
           ok = append_wf_event(SessionRoot, WfSessionId0, openagentic_events:system_init(WfSessionId, ProjectDir, #{time_context => TimeContext})),
           ok =
             append_wf_event(
               SessionRoot,
               WfSessionId0,
              openagentic_events:workflow_init(
                WorkflowId,
                WfName,
                WorkflowRelPath,
                DslHash,
                #{project_dir => to_bin(ProjectDir), controller_input => ControllerInput, time_context => TimeContext}
              )
            ),
          State0 =
            #{
              project_dir => ProjectDir,
              session_root => SessionRoot,
               workflow_id => WorkflowId,
               workflow_name => WfName,
               workflow_session_id => WfSessionId0,
               workspace_dir => WfWorkspaceDir,
               workflow_rel_path => to_bin(WorkflowRelPath),
               defaults => ensure_map(maps:get(<<"defaults">>, Wf, #{})),
               steps_by_id => ensure_map(maps:get(<<"steps_by_id">>, Wf, #{})),
               controller_input => ControllerInput,
              time_context => TimeContext,
              step_outputs => #{},
              step_attempts => #{},
              step_failures => #{},
              opts => Opts2
            },
          Start = maps:get(<<"start_step_id">>, Wf, <<>>),
          ok = append_wf_event(State0, #{type => <<"workflow.run.start">>, workflow_id => to_bin(WorkflowId), start_step_id => to_bin(Start), time_context => TimeContext}),
          {ok, to_bin(Start), State0};
        {error, Reason} ->
          {error, Reason}
      end;
    Err ->
      Err
  end.

init_continue(SessionRoot, WorkflowSessionId, Message, Opts0) ->
  %% Read existing workflow session to recover workflow.init context.
  Events = openagentic_session_store:read_events(SessionRoot, WorkflowSessionId),
  case find_workflow_init(Events) of
    {error, _} = Err ->
      Err;
    {ok, Init} ->
      WfId = maps:get(<<"workflow_id">>, Init, maps:get(workflow_id, Init, <<>>)),
      WfName = maps:get(<<"workflow_name">>, Init, maps:get(workflow_name, Init, <<>>)),
      DslPath = to_bin(maps:get(<<"dsl_path">>, Init, maps:get(dsl_path, Init, <<"workflows/three-provinces-six-ministries.v1.json">>))),
      ProjectDir0 = maps:get(<<"project_dir">>, Init, maps:get(project_dir, Init, maps:get(<<"projectDir">>, Init, maps:get(projectDir, Init, <<".">>)))),
      ProjectDir = ensure_list_str(ProjectDir0),

      %% Collect original controller_input + any prior followups + this message.
      BaseInput = to_bin(maps:get(<<"controller_input">>, Init, maps:get(controller_input, Init, <<>>))),
      Followups = [to_bin(maps:get(<<"text">>, E, maps:get(text, E, <<>>))) || E <- Events, is_controller_message(E)],
      ControllerInput =
        iolist_to_binary([
          BaseInput,
          <<"\n\n---\n\n# Followup\n\n">>,
          join_bins([X || X <- Followups, byte_size(string:trim(X)) > 0] ++ [Message], <<"\n\n">>),
          <<"\n">>
        ]),

      %% Reconstruct last outputs/failures so resuming a failed step can bind inputs and show guard reasons.
      StepOutputsAll = reconstruct_step_outputs(Events),
      StepFailuresAll = reconstruct_step_failures(Events),
      StepAttempts = #{},

      ExplicitTimeContext = openagentic_time_context:from_opts(Opts0),
      WfWorkspaceDir = workflow_workspace_dir(SessionRoot, WorkflowSessionId),
      ok = filelib:ensure_dir(filename:join([WfWorkspaceDir, "x"])),
      case openagentic_workflow_dsl:load_and_validate(ProjectDir, ensure_list_str(DslPath), Opts0) of
        {ok, Wf} ->
          Defaults = ensure_map(maps:get(<<"defaults">>, Wf, #{})),
          StepsById = ensure_map(maps:get(<<"steps_by_id">>, Wf, #{})),
          StartDefault = maps:get(<<"start_step_id">>, Wf, <<>>),
          StartStepId = pick_continue_step(Events, to_bin(StartDefault)),
          {PrevStatus, _PrevDoneIdx} = last_workflow_done(ensure_list_value(Events)),
          StartingFresh = PrevStatus =:= <<"completed">>,
          StepOutputs =
            case StartingFresh of
              true -> #{};
              false -> StepOutputsAll
            end,
          StepFailures =
            case StartingFresh of
              true -> #{};
              false -> StepFailuresAll
            end,
          TimeContext =
            case ExplicitTimeContext of
              undefined ->
                case StartingFresh of
                  true -> openagentic_time_context:resolve(Opts0);
                  false -> recover_workflow_time_context(Events, Init, Opts0)
                end;
              Ctx -> Ctx
            end,
          Opts1 = openagentic_time_context:put_in_opts(Opts0, TimeContext),
          Opts = ensure_web_answerer(Opts1, to_bin(WorkflowSessionId)),
          State0 =
            #{
              project_dir => ProjectDir,
              session_root => SessionRoot,
              workflow_id => WfId,
              workflow_name => WfName,
              workflow_session_id => WorkflowSessionId,
              workspace_dir => WfWorkspaceDir,
              workflow_rel_path => to_bin(DslPath),
              defaults => Defaults,
              steps_by_id => StepsById,
              controller_input => ControllerInput,
              time_context => TimeContext,
              step_outputs => StepOutputs,
              step_attempts => StepAttempts,
              step_failures => StepFailures,
              opts => Opts
            },
          %% Observability for the UI.
          ok = append_wf_event(State0, #{type => <<"workflow.controller.message">>, workflow_id => to_bin(WfId), text => Message}),
          ok = append_wf_event(State0, #{type => <<"workflow.run.start">>, workflow_id => to_bin(WfId), start_step_id => StartStepId, time_context => TimeContext}),
          {ok, StartStepId, State0};
        Err ->
          Err
      end
  end.

find_workflow_init(Events0) ->
  Events = ensure_list_value(Events0),
  case [E || E <- Events, is_map(E) andalso to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) =:= <<"workflow.init">>] of
    [H | _] -> {ok, H};
    [] -> {error, missing_workflow_init}
  end.

is_controller_message(E0) ->
  E = ensure_map(E0),
  to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) =:= <<"workflow.controller.message">>.

recover_workflow_time_context(Events0, Init0, Opts0) ->
  case last_workflow_run_time_context(Events0) of
    undefined ->
      case event_time_context(Init0) of
        undefined -> openagentic_time_context:resolve(Opts0);
        TimeContext -> TimeContext
      end;
    TimeContext ->
      TimeContext
  end.

last_workflow_run_time_context(Events0) ->
  Events = lists:reverse(ensure_list_value(Events0)),
  last_workflow_run_time_context_loop(Events).

last_workflow_run_time_context_loop([]) ->
  undefined;
last_workflow_run_time_context_loop([E0 | Rest]) ->
  E = ensure_map(E0),
  case to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) of
    <<"workflow.run.start">> -> event_time_context(E);
    _ -> last_workflow_run_time_context_loop(Rest)
  end.

event_time_context(E0) ->
  E = ensure_map(E0),
  case maps:get(<<"time_context">>, E, maps:get(time_context, E, undefined)) of
    undefined -> undefined;
    null -> undefined;
    TimeContext -> openagentic_time_context:resolve(#{time_context => TimeContext})
  end.

reconstruct_step_outputs(Events0) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Acc0) ->
      E = ensure_map(E0),
      T = to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
      case T of
        <<"workflow.step.output">> ->
          StepId = to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>))),
          Out = to_bin(maps:get(<<"output">>, E, maps:get(output, E, <<>>))),
          StepSid = to_bin(maps:get(<<"step_session_id">>, E, maps:get(step_session_id, E, <<>>))),
          Acc0#{StepId => #{output => Out, parsed => #{}, step_session_id => StepSid}};
        _ ->
          Acc0
      end
    end,
    #{},
    Events
  ).

reconstruct_step_failures(Events0) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Acc0) ->
      E = ensure_map(E0),
      T = to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
      case T of
        <<"workflow.guard.fail">> ->
          StepId = to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>))),
          Reasons0 = ensure_list_value(maps:get(<<"reasons">>, E, maps:get(reasons, E, []))),
          Reasons = [to_bin(X) || X <- Reasons0],
          Acc0#{StepId => Reasons};
        _ ->
          Acc0
      end
    end,
    #{},
    Events
  ).

pick_continue_step(Events0, DefaultStart0) ->
  Events = ensure_list_value(Events0),
  DefaultStart = to_bin(DefaultStart0),
  %% Semantics:
  %% - If the previous run completed: start from the workflow default start step (new input may change everything).
  %% - If the previous run failed: resume from the last started step (to fix blocking input).
  {Status, DoneIdx} = last_workflow_done(Events),
  case Status of
    <<"completed">> ->
      DefaultStart;
    <<"failed">> ->
      case last_step_id_before(Events, DoneIdx, <<"workflow.step.start">>, <<"step_id">>) of
        <<>> -> DefaultStart;
        S -> S
      end;
    _ ->
      DefaultStart
  end.

last_workflow_done(Events) ->
  %% Returns {StatusBin, Index} (0-based), or {<<>>, -1} if not found.
  last_workflow_done(Events, 0, {<<>>, -1}).

last_workflow_done([], _Idx, Acc) ->
  Acc;
last_workflow_done([E0 | Rest], Idx, {BestStatus, BestIdx}) ->
  E = ensure_map(E0),
  T = to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  Acc =
    case T of
      <<"workflow.done">> ->
        Status = to_bin(maps:get(<<"status">>, E, maps:get(status, E, <<>>))),
        {Status, Idx};
      _ ->
        {BestStatus, BestIdx}
    end,
  last_workflow_done(Rest, Idx + 1, Acc).

last_step_id_before(Events, DoneIdx, Type, Key) ->
  case DoneIdx of
    I when is_integer(I), I >= 0 ->
      Prefix = lists:sublist(Events, I),
      last_step_id_before_loop(Prefix, to_bin(Type), to_bin(Key), <<>>);
    _ ->
      last_step_id_before_loop(Events, to_bin(Type), to_bin(Key), <<>>)
  end.

last_step_id_before_loop([], _Type, _Key, Best) ->
  Best;
last_step_id_before_loop([E0 | Rest], Type, Key, Best0) ->
  E = ensure_map(E0),
  T = to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))),
  Best =
    case T =:= Type of
      true ->
        case Key of
          <<"step_id">> -> to_bin(maps:get(<<"step_id">>, E, maps:get(step_id, E, <<>>)));
          _ -> to_bin(maps:get(Key, E, <<>>))
        end;
      false ->
        Best0
    end,
  last_step_id_before_loop(Rest, Type, Key, Best).

execute(StartStepId, State0) ->
  try
    run_loop(to_bin(StartStepId), State0)
  catch
    Class:Reason:Stack ->
      Extra = #{error_class => Class, error_reason => Reason, stacktrace => Stack},
      _ =
        append_wf_event(
          State0,
          openagentic_events:workflow_done(
            wf_id(State0),
            maps:get(workflow_name, State0, <<>>),
            <<"failed">>,
            to_bin({Class, Reason}),
            Extra
          )
        ),
      {error, {Class, Reason}}
  end.

ensure_web_answerer(Opts0, WorkflowSessionId) ->
  Opts = ensure_map(Opts0),
  case maps:get(web_user_answerer, Opts, undefined) of
    F when is_function(F, 1) ->
      Opts;
    _ ->
      case to_bool_default(maps:get(web_hil, Opts, false), false) of
        true ->
          Opts#{web_user_answerer => fun (Q) -> openagentic_web_q:ask(WorkflowSessionId, Q) end};
        false ->
          Opts
      end
  end.

%% ---- main loop ----

run_loop(StepId0, State0) ->
  StepId = to_bin(StepId0),
  case StepId of
    <<>> ->
      finalize(State0, <<"failed">>, <<"missing start step">>);
    _ ->
      StepsById = maps:get(steps_by_id, State0),
      case maps:find(StepId, StepsById) of
        error ->
          finalize(State0, <<"failed">>, iolist_to_binary([<<"unknown step: ">>, StepId]));
        {ok, StepRaw0} ->
          StepRaw = ensure_map(StepRaw0),
          Attempt0 = maps:get(StepId, maps:get(step_attempts, State0, #{}), 0),
          Attempt = Attempt0 + 1,
          MaxAttempts = step_max_attempts(StepRaw, State0),
          case Attempt =< MaxAttempts of
            false ->
              Msg = iolist_to_binary([<<"max_attempts exceeded for step ">>, StepId]),
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"max_attempts">>, [Msg])),
              finalize(State0, <<"failed">>, Msg);
            true ->
              State1 = put_in(State0, [step_attempts, StepId], Attempt),
              case step_executor_kind(StepRaw) of
                <<"fanout_join">> -> run_fanout_join_step(StepId, StepRaw, Attempt, State1);
                _ -> run_one_step(StepId, StepRaw, Attempt, State1)
              end
          end
      end
  end.

run_one_step(StepId, StepRaw, Attempt, State0) ->
  run_one_step_attempt(StepId, StepRaw, Attempt, 0, State0).

run_one_step_attempt(StepId, StepRaw, Attempt, RetryCount0, State0) ->
  Role = to_bin(get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = to_bin(StepSessionId0),

  ok = append_wf_event(State0, openagentic_events:workflow_step_start(wf_id(State0), StepId, Role, Attempt, StepSessionId)),

  case resolve_prompt(State0, StepRaw) of
    {ok, PromptText} ->
      InputText = bind_input(State0, StepRaw),
      Failures = maps:get(StepId, maps:get(step_failures, State0, #{}), []),
      ControllerText = maps:get(controller_input, State0, <<>>),
      UserPrompt = build_user_prompt(PromptText, ControllerText, InputText, Attempt, Failures),
      ExecRes = run_step_executor_with_timeout(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
      case ExecRes of
        {ok, StepOut0} ->
          StepOut = to_bin(StepOut0),
          OutFormat = infer_output_format(StepRaw),
          ok =
            append_wf_event(
              State0,
              openagentic_events:workflow_step_output(wf_id(State0), StepId, Attempt, StepSessionId, StepOut, OutFormat)
            ),
          case eval_step_output(StepRaw, StepOut) of
            {ok, Parsed} ->
              State1 = put_in(State0, [step_outputs, StepId], #{output => StepOut, parsed => Parsed, step_session_id => StepSessionId}),
              {Next, TransitionReason} = step_next(StepRaw, Parsed),
              ok = append_wf_event(State1, openagentic_events:workflow_step_pass(wf_id(State1), StepId, Attempt, Next)),
              ok = append_wf_event(State1, openagentic_events:workflow_transition(wf_id(State1), StepId, <<"pass">>, Next, TransitionReason)),
              case Next of
                null -> finalize(State1, <<"completed">>, StepOut);
                _ -> run_loop(Next, State1)
              end;
            {error, Reasons} ->
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"guards">>, Reasons)),
              NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"guard_failed">>)),
              case NextFail of
                null -> finalize(State0, <<"failed">>, join_bins(Reasons, <<"\n">>));
                _ ->
                  %% Persist failure reasons in memory so retries can self-correct.
                  StateFail = put_in(State0, [step_failures, StepId], Reasons),
                  run_loop(NextFail, StateFail)
              end
          end;
        {error, Reason} ->
          ReasonBin = to_bin(Reason),
          case maybe_retry_transient_provider_error(State0, StepId, StepRaw, Attempt, RetryCount0, ReasonBin) of
            {retry, RetryState} ->
              run_one_step_attempt(StepId, StepRaw, Attempt, RetryCount0 + 1, RetryState);
            no_retry ->
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"executor">>, [ReasonBin])),
              NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"executor_failed">>)),
              case NextFail of
                null -> finalize(State0, <<"failed">>, ReasonBin);
                _ ->
                  StateFail = put_in(State0, [step_failures, StepId], [ReasonBin]),
                  run_loop(NextFail, StateFail)
              end
          end
      end;
    {error, Reason} ->
      ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"prompt">>, [to_bin(Reason)])),
      finalize(State0, <<"failed">>, to_bin(Reason))
  end.

run_fanout_join_step(StepId, StepRaw, Attempt, State0) ->
  Role = to_bin(get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = to_bin(StepSessionId0),
  ok = append_wf_event(State0, openagentic_events:workflow_step_start(wf_id(State0), StepId, Role, Attempt, StepSessionId)),
  FanoutCfg = ensure_map(get_any(StepRaw, [<<"fanout">>, fanout], #{})),
  FanoutSteps = [to_bin(S) || S <- ensure_list_value(get_any(FanoutCfg, [<<"steps">>, steps], []))],
  JoinStep = step_ref(FanoutCfg, [<<"join">>, join]),
  case collect_fanout_results(FanoutSteps, State0) of
    {ok, Results} ->
      State1 = persist_fanout_successes(FanoutSteps, Results, State0),
      ok = append_wf_event(State1, openagentic_events:workflow_step_pass(wf_id(State1), StepId, Attempt, JoinStep)),
      ok = append_wf_event(State1, openagentic_events:workflow_transition(wf_id(State1), StepId, <<"pass">>, JoinStep, <<"fanout_join_completed">>)),
      case JoinStep of
        null -> finalize(State1, <<"completed">>, <<"fanout_join_completed">>);
        _ -> run_loop(JoinStep, State1)
      end;
    {error, Reasons} ->
      ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"fanout">>, Reasons)),
      NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
      ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"fanout_join_failed">>)),
      case NextFail of
        null -> finalize(State0, <<"failed">>, join_bins(Reasons, <<"\n">>));
        _ ->
          StateFail = put_in(State0, [step_failures, StepId], Reasons),
          run_loop(NextFail, StateFail)
      end
  end.

collect_fanout_results(StepIds0, State0) ->
  StepIds = uniq_bins(StepIds0),
  Parent = self(),
  Sink = fun (Ev) -> Parent ! {wf_event, Ev}, ok end,
  Pending =
    lists:foldl(
      fun (LeafStepId, Acc) ->
        {Pid, Ref} =
          spawn_monitor(
            fun () ->
              Parent ! {fanout_result, LeafStepId, safe_run_fanout_child(LeafStepId, State0, Sink)}
            end
          ),
        Acc#{Ref => #{step_id => LeafStepId, pid => Pid}}
      end,
      #{},
      StepIds
    ),
  wait_for_fanout(Pending, #{}, State0).

wait_for_fanout(Pending, Results, _State0) when map_size(Pending) =:= 0 ->
  finalize_fanout_results(Results);
wait_for_fanout(Pending, Results0, State0) ->
  receive
    {wf_event, Ev} ->
      ok = append_wf_event(State0, Ev),
      wait_for_fanout(Pending, Results0, State0);
    {fanout_result, StepId, Result} ->
      wait_for_fanout(Pending, Results0#{StepId => Result}, State0);
    {'DOWN', Ref, process, _Pid, Reason} ->
      case maps:take(Ref, Pending) of
        error ->
          wait_for_fanout(Pending, Results0, State0);
        {#{step_id := StepId}, Pending1} ->
          Results1 =
            case maps:is_key(StepId, Results0) of
              true -> Results0;
              false -> Results0#{StepId => down_reason_to_result(StepId, Reason)}
            end,
          wait_for_fanout(Pending1, Results1, State0)
      end
  end.

finalize_fanout_results(Results) ->
  case [format_fanout_reason(StepId, Reason) || {StepId, {error, Reason}} <- maps:to_list(Results)] of
    [] -> {ok, Results};
    Reasons -> {error, Reasons}
  end.

down_reason_to_result(_StepId, normal) ->
  {error, [<<"fanout child exited before returning a result">>]};
down_reason_to_result(_StepId, Reason) ->
  {error, [iolist_to_binary(io_lib:format("fanout child crashed: ~p", [Reason]))]}.

safe_run_fanout_child(StepId, State0, Sink) ->
  try
    run_fanout_child(StepId, State0, Sink)
  catch
    Class:Reason ->
      {error, [iolist_to_binary(io_lib:format("fanout child crashed: ~p:~p", [Class, Reason]))]}
  end.

run_fanout_child(StepId, State0, Sink) ->
  StepRaw = ensure_map(maps:get(StepId, maps:get(steps_by_id, State0))),
  ChildState = State0#{workflow_event_sink => Sink},
  run_fanout_child_attempt(StepId, StepRaw, ChildState).

run_fanout_child_attempt(StepId, StepRaw, State0) ->
  Attempt0 = maps:get(StepId, maps:get(step_attempts, State0, #{}), 0),
  Attempt = Attempt0 + 1,
  MaxAttempts = step_max_attempts(StepRaw, State0),
  case Attempt =< MaxAttempts of
    false ->
      Msg = iolist_to_binary([<<"max_attempts exceeded for step ">>, StepId]),
      ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"max_attempts">>, [Msg])),
      {error, [Msg]};
    true ->
      State1 = put_in(State0, [step_attempts, StepId], Attempt),
      run_fanout_child_once(StepId, StepRaw, Attempt, State1)
  end.

run_fanout_child_once(StepId, StepRaw, Attempt, State0) ->
  Role = to_bin(get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = to_bin(StepSessionId0),
  ok = append_wf_event(State0, openagentic_events:workflow_step_start(wf_id(State0), StepId, Role, Attempt, StepSessionId)),
  case resolve_prompt(State0, StepRaw) of
    {ok, PromptText} ->
      InputText = bind_input(State0, StepRaw),
      Failures = maps:get(StepId, maps:get(step_failures, State0, #{}), []),
      ControllerText = maps:get(controller_input, State0, <<>>),
      UserPrompt = build_user_prompt(PromptText, ControllerText, InputText, Attempt, Failures),
      ExecRes = run_step_executor_with_timeout(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
      case ExecRes of
        {ok, StepOut0} ->
          StepOut = to_bin(StepOut0),
          OutFormat = infer_output_format(StepRaw),
          case eval_step_output(StepRaw, StepOut) of
            {ok, Parsed} ->
              {ok, #{attempt => Attempt, output => StepOut, parsed => Parsed, output_format => OutFormat, step_session_id => StepSessionId}};
            {error, Reasons} ->
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"guards">>, Reasons)),
              NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"guard_failed">>)),
              case NextFail of
                StepId ->
                  StateFail = put_in(State0, [step_failures, StepId], Reasons),
                  run_fanout_child_attempt(StepId, StepRaw, StateFail);
                null ->
                  {error, Reasons};
                _ ->
                  {error, [iolist_to_binary([<<"unsupported fanout on_fail route: ">>, to_bin(NextFail)]) | Reasons]}
              end
          end;
        {error, Reason} ->
          ReasonBin = to_bin(Reason),
          ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"executor">>, [ReasonBin])),
          NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
          ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"executor_failed">>)),
          case NextFail of
            StepId ->
              StateFail = put_in(State0, [step_failures, StepId], [ReasonBin]),
              run_fanout_child_attempt(StepId, StepRaw, StateFail);
            null ->
              {error, [ReasonBin]};
            _ ->
              {error, [iolist_to_binary([<<"unsupported fanout on_fail route: ">>, to_bin(NextFail)]), ReasonBin]}
          end
      end;
    {error, Reason} ->
      ReasonBin = to_bin(Reason),
      ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"prompt">>, [ReasonBin])),
      {error, [ReasonBin]}
  end.

persist_fanout_successes(StepIds, Results, State0) ->
  lists:foldl(
    fun (StepId, AccState0) ->
      {ok, #{attempt := Attempt, output := StepOut, parsed := Parsed, output_format := OutFormat, step_session_id := StepSessionId}} = maps:get(StepId, Results),
      AccState1 = put_in(AccState0, [step_outputs, StepId], #{output => StepOut, parsed => Parsed, step_session_id => StepSessionId}),
      ok = append_wf_event(AccState1, openagentic_events:workflow_step_output(wf_id(AccState1), StepId, Attempt, StepSessionId, StepOut, OutFormat)),
      ok = append_wf_event(AccState1, openagentic_events:workflow_step_pass(wf_id(AccState1), StepId, Attempt, null)),
      ok = append_wf_event(AccState1, openagentic_events:workflow_transition(wf_id(AccState1), StepId, <<"pass">>, null, <<"fanout_leaf_completed">>)),
      AccState1
    end,
    State0,
    StepIds
  ).

format_fanout_reason(StepId, Reasons) when is_list(Reasons) ->
  iolist_to_binary([StepId, <<": ">>, join_bins(Reasons, <<"; ">>)]);
format_fanout_reason(StepId, Reason) ->
  iolist_to_binary([StepId, <<": ">>, to_bin(Reason)]).

%% ---- executor ----

run_step_executor_with_timeout(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  TimeoutMs = step_timeout_ms(StepRaw, State0),
  Parent = self(),
  Ref = make_ref(),
  {Pid, MRef} =
    spawn_monitor(
      fun () ->
        Res = run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
        Parent ! {step_exec_result, Ref, Res}
      end
    ),
  receive
    {step_exec_result, Ref, Res0} ->
      _ = erlang:demonitor(MRef, [flush]),
      Res0;
    {'DOWN', MRef, process, Pid, Reason} ->
      %% Result and DOWN may race; allow a small grace window to pick up the result if it was sent.
      receive
        {step_exec_result, Ref, Res1} -> Res1
      after 50 ->
        {error, {executor_crashed, Reason}}
      end
  after TimeoutMs ->
    _ = catch exit(Pid, kill),
    _ = erlang:demonitor(MRef, [flush]),
    {error, {step_timeout, TimeoutMs}}
  end.

maybe_retry_transient_provider_error(State0, StepId, StepRaw, Attempt, RetryCount0, Reason0) ->
  Reason = to_bin(Reason0),
  case retry_policy(StepRaw) of
    #{enabled := true, max_retries := MaxRetries, backoff_ms := BackoffMs}
      when RetryCount0 < MaxRetries ->
      case is_transient_provider_error(Reason0) of
        true ->
          RetryCount = RetryCount0 + 1,
          ok =
            append_wf_event(
              State0,
              #{
                type => <<"workflow.step.retry">>,
                workflow_id => wf_id(State0),
                step_id => StepId,
                attempt => Attempt,
                retry_count => RetryCount,
                max_retries => MaxRetries,
                backoff_ms => BackoffMs,
                reason => Reason,
                retry_kind => <<"transient_provider_error">>
              }
            ),
          maybe_sleep_ms(BackoffMs),
          {retry, put_in(State0, [step_failures, StepId], [Reason])};
        false ->
          no_retry
      end;
    _ ->
      no_retry
  end.

retry_policy(StepRaw) ->
  Policy0 = ensure_map(get_any(StepRaw, [<<"retry_policy">>, retry_policy], #{})),
  Enabled = to_bool_default(get_any(Policy0, [<<"transient_provider_errors">>, transient_provider_errors], false), false),
  MaxRetries0 = int_or_default(get_any(Policy0, [<<"max_retries">>, max_retries], 0), 0),
  BackoffMs0 = int_or_default(get_any(Policy0, [<<"backoff_ms">>, backoff_ms], 1000), 1000),
  #{enabled => Enabled, max_retries => clamp_int(MaxRetries0, 0, 3), backoff_ms => clamp_int(BackoffMs0, 1, 30000)}.

maybe_sleep_ms(Ms) when is_integer(Ms), Ms > 0 ->
  timer:sleep(Ms),
  ok;
maybe_sleep_ms(_Ms) ->
  ok.

is_transient_provider_error(timeout) ->
  true;
is_transient_provider_error({step_timeout, _}) ->
  true;
is_transient_provider_error({http_stream_error, _}) ->
  true;
is_transient_provider_error({httpc_request_failed, _}) ->
  true;
is_transient_provider_error(stream_ended_without_response_completed) ->
  true;
is_transient_provider_error({provider_error, Reason}) ->
  is_transient_provider_error(Reason);
is_transient_provider_error({executor_crashed, Reason}) ->
  is_transient_provider_error(Reason);
is_transient_provider_error(Reason0) ->
  Reason = string:lowercase(string:trim(to_bin(Reason0))),
  Deny =
    [
      <<"unauthorized">>,
      <<"forbidden">>,
      <<"authentication">>,
      <<"invalid api key">>,
      <<"permission">>,
      <<"quota">>,
      <<"billing">>,
      <<"payment">>,
      <<"bad request">>,
      <<"invalid request">>,
      <<"validation">>,
      <<"model not found">>,
      <<"unsupported">>
    ],
  Allow =
    [
      <<"timeout">>,
      <<"timed out">>,
      <<"stream ended without response completed">>,
      <<"http_stream_error">>,
      <<"connection reset">>,
      <<"connection aborted">>,
      <<"temporarily unavailable">>,
      <<"econnreset">>,
      <<"broken pipe">>
    ],
  (not lists:any(fun (Pat) -> binary:match(Reason, Pat) =/= nomatch end, Deny))
  andalso lists:any(fun (Pat) -> binary:match(Reason, Pat) =/= nomatch end, Allow).

run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts = maps:get(opts, State0, #{}),
  Ctx =
    #{
      project_dir => to_bin(maps:get(project_dir, State0)),
      session_root => to_bin(maps:get(session_root, State0)),
      workflow_id => wf_id(State0),
      workflow_session_id => to_bin(maps:get(workflow_session_id, State0)),
      step_id => StepId,
      role => Role,
      attempt => Attempt,
      step_session_id => to_bin(StepSessionId0),
      time_context => maps:get(time_context, State0, undefined),
      user_prompt => UserPrompt
    },
  case maps:get(step_executor, Opts, undefined) of
    F1 when is_function(F1, 1) ->
      F1(Ctx);
    F2 when is_function(F2, 2) ->
      F2(Ctx, StepRaw);
    _ ->
      default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw)
  end.

default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts0 = maps:get(opts, State0, #{}),
  MaxSteps = step_max_steps(StepRaw, State0, maps:get(max_steps, Opts0, ?DEFAULT_MAX_STEPS)),
  {Gate, AllowedTools} = tool_policy_for_step(StepRaw, State0),
  WfId = wf_id(State0),
  WfSid = to_bin(maps:get(workflow_session_id, State0, <<>>)),
  StepSessionIdBin = to_bin(StepSessionId0),
  %% Bridge step events (tool.use/tool.result/user.question/assistant.* etc.) into the workflow session,
  %% so the web UI can observe and answer HITL prompts.
   BridgeSink =
      fun (Ev0) ->
        Ev = ensure_map(Ev0),
       StepSeq = maps:get(seq, Ev, maps:get(<<"seq">>, Ev, undefined)),
       StepTs = maps:get(ts, Ev, maps:get(<<"ts">>, Ev, undefined)),
      %% NOTE: jsone:encode/1 crashes on `undefined`. Step events like assistant.delta
      %% are transient and may not carry seq/ts, so only include them when present.
      Extra0 = #{},
      Extra1 =
        case StepSeq of
          undefined -> Extra0;
          _ -> Extra0#{step_seq => StepSeq}
        end,
      Extra =
        case StepTs of
          undefined -> Extra1;
          _ -> Extra1#{step_ts => StepTs}
        end,
       _ = append_wf_event(State0, openagentic_events:workflow_step_event(WfId, StepId, StepSessionIdBin, Ev, Extra)),
       _ = (catch openagentic_workflow_mgr:note_progress(WfSid, Ev)),
        ok
      end,
  WebAnswerer0 = maps:get(web_user_answerer, Opts0, undefined),
  WebAnswerer =
    case WebAnswerer0 of
      F when is_function(F, 1) -> F;
      _ -> undefined
    end,
  UserAnswerer =
    case WebAnswerer of
      undefined ->
        maps:get(user_answerer, Opts0, undefined);
      _ ->
        WebAnswerer
    end,
  %% Ensure the permission gate uses the effective userAnswerer for this run.
  %% In web mode, the CLI-provided user_answerer may be unsupported (io:get_line/1 -> {error,enotsup}).
  Gate2 =
    case UserAnswerer of
      AnswererFun when is_function(AnswererFun, 1) ->
        GateMap = ensure_map(Gate),
        GateMap#{user_answerer => AnswererFun};
      _ -> ensure_map(Gate)
    end,
  RuntimeOpts =
    Opts0#{
      project_dir => maps:get(project_dir, State0),
      workspace_dir => maps:get(workspace_dir, State0, undefined),
      cwd => maps:get(project_dir, State0),
      session_root => maps:get(session_root, State0),
      resume_session_id => StepSessionId0,
      system_prompt => role_system_prompt(Role, StepId, Attempt),
      max_steps => MaxSteps,
      permission_gate => Gate2,
      allowed_tools => AllowedTools,
      user_answerer => UserAnswerer,
      event_sink => BridgeSink
    },
  case openagentic_runtime:query(UserPrompt, RuntimeOpts) of
    {ok, #{final_text := Txt}} -> {ok, Txt};
    {ok, _Other} -> {ok, <<>>};
    {error, Reason} -> {error, Reason}
  end.

role_system_prompt(Role, StepId, Attempt) ->
  iolist_to_binary([
    <<"You are an agent role='">>,
    Role,
    <<"' executing step_id='">>,
    StepId,
    <<"' attempt=">>,
    integer_to_binary(Attempt),
    <<". Follow the step prompt strictly and produce the required output format.">>
  ]).

tool_policy_for_step(StepRaw, State0) ->
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  StepPolicy0 = ensure_map(get_any(StepRaw, [<<"tool_policy">>, tool_policy], #{})),
  DefaultPolicy0 = ensure_map(get_any(Defaults, [<<"tool_policy">>, tool_policy], #{})),
  Policy = maps:merge(DefaultPolicy0, StepPolicy0),

  Mode = to_bin(get_any(Policy, [<<"mode">>, mode], <<"default">>)),
  Allow0 = ensure_list_value(get_any(Policy, [<<"allow">>, allow], [])),
  Deny0 = ensure_list_value(get_any(Policy, [<<"deny">>, deny], [])),

  Allow = uniq_bins([to_bin(X) || X <- Allow0]),
  Deny = uniq_bins([to_bin(X) || X <- Deny0]),

  UserAnswerer = maps:get(user_answerer, maps:get(opts, State0, #{}), undefined),
  Gate =
    case Mode of
      <<"bypass">> -> openagentic_permissions:bypass();
      <<"deny">> -> openagentic_permissions:deny();
      <<"prompt">> -> openagentic_permissions:prompt(UserAnswerer);
      _ -> openagentic_permissions:default(UserAnswerer)
    end,

  AllowedTools =
    case {Allow, Deny} of
      {[], []} ->
        undefined;
      {A, _} when A =/= [] ->
        ensure_ask_user(A);
      {[], D} ->
        All = all_known_tool_names(),
        ensure_ask_user([T || T <- All, not lists:member(T, D)])
    end,
  {Gate, AllowedTools}.

ensure_ask_user(L0) ->
  L = uniq_bins([to_bin(X) || X <- ensure_list_value(L0)]),
  case lists:member(<<"AskUserQuestion">>, L) of
    true -> L;
    false -> [<<"AskUserQuestion">> | L]
  end.

all_known_tool_names() ->
  [
    <<"AskUserQuestion">>,
    <<"List">>,
    <<"Read">>,
    <<"Glob">>,
    <<"Grep">>,
    <<"Write">>,
    <<"Edit">>,
    <<"Bash">>,
    <<"WebFetch">>,
    <<"WebSearch">>,
    <<"Skill">>,
    <<"SlashCommand">>,
    <<"NotebookEdit">>,
    <<"lsp">>,
    <<"TodoWrite">>,
    <<"Task">>,
    <<"Echo">>
  ].

%% ---- prompt & input binding ----

resolve_prompt(State0, StepRaw) ->
  Prompt0 = ensure_map(get_any(StepRaw, [<<"prompt">>, prompt], #{})),
  T = to_bin(get_any(Prompt0, [<<"type">>, type], <<>>)),
  ProjectDir = maps:get(project_dir, State0),
  case T of
    <<"inline">> ->
      Txt = to_bin(get_any(Prompt0, [<<"text">>, text], <<>>)),
      case byte_size(string:trim(Txt)) > 0 of
        true -> {ok, Txt};
        false -> {error, <<"prompt.text is required">>}
      end;
    <<"file">> ->
      Rel = to_bin(get_any(Prompt0, [<<"path">>, path], <<>>)),
      case openagentic_fs:resolve_project_path(ProjectDir, Rel) of
        {ok, Abs} ->
          case file:read_file(Abs) of
            {ok, Bin} -> {ok, Bin};
            _ -> {error, <<"prompt file read failed">>}
          end;
        _ ->
          {error, <<"prompt path unsafe">>}
      end;
    _ ->
      {error, <<"unknown prompt type">>}
  end.

bind_input(State0, StepRaw) ->
  Input0 = ensure_map(get_any(StepRaw, [<<"input">>, input], #{})),
  T = to_bin(get_any(Input0, [<<"type">>, type], <<>>)),
  Role = to_bin(get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepOutputs = maps:get(step_outputs, State0, #{}),
  case T of
    <<"controller_input">> ->
      maps:get(controller_input, State0, <<>>);
    <<"step_output">> ->
      From = to_bin(get_any(Input0, [<<"step_id">>, step_id], <<>>)),
      case maps:get(From, StepOutputs, undefined) of
        #{output := Out} -> maybe_filter_tasks_input(Role, to_bin(Out));
        _ -> <<>>
      end;
    <<"merge">> ->
      Sources = ensure_list_value(get_any(Input0, [<<"sources">>, sources], [])),
      merge_sources(Sources, StepOutputs, 0, []);
    _ ->
      <<>>
  end.

maybe_filter_tasks_input(Role, OutBin) ->
  case is_ministry_role(Role) of
    false ->
      OutBin;
    true ->
      case (catch openagentic_json:decode(OutBin)) of
        #{<<"tasks">> := Tasks0} = Obj when is_list(Tasks0) ->
          Tasks =
            [
              T0
              || T0 <- Tasks0,
                 is_map(T0),
                 to_bin(maps:get(<<"ministry">>, T0, maps:get(ministry, T0, <<>>))) =:= Role
            ],
          %% Keep all other keys intact, only filter `tasks`.
          openagentic_json:encode(Obj#{<<"tasks">> => Tasks});
        _ ->
          OutBin
      end
  end.

is_ministry_role(<<"hubu">>) -> true;
is_ministry_role(<<"libu">>) -> true;
is_ministry_role(<<"bingbu">>) -> true;
is_ministry_role(<<"xingbu">>) -> true;
is_ministry_role(<<"gongbu">>) -> true;
is_ministry_role(<<"libu_hr">>) -> true;
is_ministry_role(_) -> false.

merge_sources([], _StepOutputs, _Idx, AccRev) ->
  iolist_to_binary(lists:reverse(AccRev));
merge_sources([Src0 | Rest], StepOutputs, Idx, AccRev) ->
  Src = ensure_map(Src0),
  T = to_bin(get_any(Src, [<<"type">>, type], <<>>)),
  Chunk =
    case T of
      <<"step_output">> ->
        Sid = to_bin(get_any(Src, [<<"step_id">>, step_id], <<>>)),
        case maps:get(Sid, StepOutputs, undefined) of
          #{output := Out} -> to_bin(Out);
          _ -> <<>>
        end;
      <<"controller_input">> ->
        <<>>;
      _ ->
        <<>>
    end,
  case byte_size(string:trim(Chunk)) > 0 of
    false ->
      merge_sources(Rest, StepOutputs, Idx, AccRev);
    true ->
      Header = iolist_to_binary([<<"\n\n--- source ">>, integer_to_binary(Idx + 1), <<" (">>, T, <<") ---\n\n">>]),
      merge_sources(Rest, StepOutputs, Idx + 1, [Chunk, Header | AccRev])
  end.

build_user_prompt(PromptText, ControllerText0, InputText0, _Attempt0, Failures0) ->
  Failures = [to_bin(X) || X <- ensure_list_value(Failures0)],
  ControllerText = to_bin(ControllerText0),
  InputText = to_bin(InputText0),
  %% IMPORTANT: Keep these separators ASCII-only so the assembled prompt is always valid UTF-8.
  %% Otherwise, session persistence may sanitize it into a byte dump (<<...>>) and the model
  %% won't see the real user intent.
  Base =
    iolist_to_binary([
      PromptText,
      <<"\n\n---\n\n# Controller\n\n">>,
      ControllerText,
      <<"\n\n---\n\n# Input\n\n">>,
      InputText,
      <<"\n">>
    ]),
  case Failures =/= [] of
    true ->
      Hint =
        iolist_to_binary([
          <<"\n\n---\n\n# Previous failure reasons (must fix)\n\n">>,
          <<"- ">>, join_bins(Failures, <<"\n- ">>), <<"\n\n">>,
          <<"Fix the above reasons and re-output strictly; do NOT ask questions; do NOT change required headings.\n">>
        ]),
      iolist_to_binary([Base, Hint]);
    false ->
      Base
  end.

infer_output_format(StepRaw) ->
  OutC = ensure_map(get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  T = to_bin(get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"decision">> -> <<"json">>;
    <<"json_object">> -> <<"json">>;
    _ -> <<"markdown">>
  end.

%% ---- evaluation ----

eval_step_output(StepRaw, Output0) ->
  Output = to_bin(Output0),
  OutC = ensure_map(get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  case eval_output_contract(OutC, Output) of
    {ok, Parsed} ->
      Guards = ensure_list_value(get_any(StepRaw, [<<"guards">>, guards], [])),
      case eval_guards(Guards, Output, Parsed) of
        ok -> {ok, Parsed};
        {error, Reasons} -> {error, Reasons}
      end;
    {error, Reasons} ->
      {error, Reasons}
  end.

eval_output_contract(OutC, Output) ->
  T = to_bin(get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"markdown_sections">> ->
      Req = ensure_list_value(get_any(OutC, [<<"required">>, required], [])),
      case missing_sections(Req, Output) of
        [] -> {ok, #{type => markdown}};
        Missing ->
          {error, [iolist_to_binary([<<"missing sections: ">>, join_bins([to_bin(M) || M <- Missing], <<", ">>)])]}
      end;
    <<"decision">> ->
      case parse_json_object(Output) of
        {ok, Obj} ->
          Allowed = [to_bin(X) || X <- ensure_list_value(get_any(OutC, [<<"allowed">>, allowed], []))],
          Decision = to_bin(get_any(Obj, [<<"decision">>, decision], <<>>)),
          case lists:member(Decision, Allowed) of
            true -> {ok, Obj#{type => decision}};
            false -> {error, [<<"invalid decision">>]}
          end;
        {error, _} ->
          {error, [<<"decision output must be a JSON object">>]}
      end;
    <<"json_object">> ->
      case parse_json_object(Output) of
        {ok, Obj} -> {ok, Obj#{type => json_object}};
        {error, _} -> {error, [<<"output must be a JSON object">>]}
      end;
    _ ->
      {ok, #{type => unknown}}
  end.

eval_guards([], _Output, _Parsed) ->
  ok;
eval_guards([G0 | Rest], Output, Parsed) ->
  G = ensure_map(G0),
  T = to_bin(get_any(G, [<<"type">>, type], <<>>)),
  Res =
    case T of
      <<"max_words">> ->
        Limit = int_or_default(get_any(G, [<<"value">>, value], undefined), 0),
        Count = word_count(Output),
        case (Limit > 0 andalso Count > Limit) of
          true -> {error, [iolist_to_binary([<<"max_words exceeded: ">>, integer_to_binary(Count), <<">">>, integer_to_binary(Limit)])]};
          false -> ok
        end;
      <<"regex_must_match">> ->
        Pat = to_bin(get_any(G, [<<"pattern">>, pattern], <<>>)),
        case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
          match -> ok;
          _ -> {error, [<<"regex_must_match failed">>]}
        end;
      <<"markdown_sections">> ->
        Req = ensure_list_value(get_any(G, [<<"required">>, required], [])),
        case missing_sections(Req, Output) of
          [] -> ok;
          Missing -> {error, [iolist_to_binary([<<"missing sections: ">>, join_bins([to_bin(M) || M <- Missing], <<", ">>)])]}
        end;
      <<"decision_requires_reasons">> ->
        When = to_bin(get_any(G, [<<"when">>, 'when'], <<>>)),
        Decision = to_bin(get_any(Parsed, [<<"decision">>, decision], <<>>)),
        case Decision =:= When of
          false -> ok;
          true ->
            ReasonsList = ensure_list_value(get_any(Parsed, [<<"reasons">>, reasons], [])),
            ChangesList = ensure_list_value(get_any(Parsed, [<<"required_changes">>, required_changes], [])),
            case (ReasonsList =/= []) andalso (ChangesList =/= []) of
              true -> ok;
              false -> {error, [<<"decision_requires_reasons failed">>]}
            end
        end;
      <<"requires_evidence">> ->
        %% v1 runner: advisory (enforced in async control plane later).
        ok;
      _ ->
        ok
    end,
  case Res of
    ok -> eval_guards(Rest, Output, Parsed);
    {error, Reasons} -> {error, Reasons}
  end.

step_next(StepRaw0, Parsed0) ->
  StepRaw = ensure_map(StepRaw0),
  Parsed = ensure_map(Parsed0),
  OnDecision0 = get_any(StepRaw, [<<"on_decision">>, on_decision], undefined),
  OnDecision =
    case OnDecision0 of
      M when is_map(M) -> M;
      L when is_list(L) -> maps:from_list(L);
      _ -> #{}
    end,
  case maps:size(OnDecision) > 0 of
    false ->
      {step_ref(StepRaw, [<<"on_pass">>, on_pass]), <<>>};
    true ->
      Decision0 = to_bin(get_any(Parsed, [<<"decision">>, decision], <<>>)),
      Decision = string:trim(Decision0),
      case byte_size(Decision) > 0 of
        false ->
          {step_ref(StepRaw, [<<"on_pass">>, on_pass]), <<>>};
        true ->
          Key = string:lowercase(Decision),
          Next0 = maps:get(Key, OnDecision, maps:get(Decision, OnDecision, undefined)),
          Next =
            case Next0 of
              undefined -> step_ref(StepRaw, [<<"on_pass">>, on_pass]);
              V -> V
            end,
          {Next, iolist_to_binary([<<"decision=">>, Decision])}
      end
  end.

missing_sections(Req0, Output0) ->
  Output = to_bin(Output0),
  Req = [to_bin(X) || X <- ensure_list_value(Req0)],
  [R || R <- Req, not has_section(R, Output)].

has_section(Title0, Output0) ->
  Title = string:trim(to_bin(Title0)),
  Output = to_bin(Output0),
  case byte_size(Title) of
    0 -> true;
    _ ->
      Pat = iolist_to_binary([<<"(?m)^\\s*#+\\s+">>, re_escape(Title), <<"\\s*$">>]),
      case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
        match -> true;
        _ -> false
      end
  end.

re_escape(Bin0) ->
  Bin = to_bin(Bin0),
  lists:foldl(
    fun ({From, To}, Acc) -> binary:replace(Acc, From, To, [global]) end,
    Bin,
    [
      {<<"\\">>, <<"\\\\">>},
      {<<".">>, <<"\\.">>},
      {<<"+">>, <<"\\+">>},
      {<<"*">>, <<"\\*">>},
      {<<"?">>, <<"\\?">>},
      {<<"^">>, <<"\\^">>},
      {<<"$">>, <<"\\$">>},
      {<<"(">>, <<"\\(">>},
      {<<")">>, <<"\\)">>},
      {<<"[">>, <<"\\[">>},
      {<<"]">>, <<"\\]">>},
      {<<"{">>, <<"\\{">>},
      {<<"}">>, <<"\\}">>},
      {<<"|">>, <<"\\|">>}
    ]
  ).

word_count(Text0) ->
  Text = to_bin(Text0),
  Parts = re:split(Text, <<"\\s+">>, [unicode, {return, list}]),
  length([P || P <- Parts, string:trim(P) =/= ""]).

parse_json_object(Output0) ->
  Output = string:trim(to_bin(Output0)),
  Bin = strip_code_fences(Output),
  try
    Obj = openagentic_json:decode(Bin),
    case is_map(Obj) of
      true -> {ok, Obj};
      false -> {error, not_object}
    end
  catch
    _:_ -> {error, invalid_json}
  end.

strip_code_fences(Bin0) ->
  Bin = to_bin(Bin0),
  case re:run(Bin, <<"(?s)^```[a-zA-Z0-9_-]*\\s*(\\{.*\\})\\s*```\\s*$">>, [{capture, [1], binary}, unicode]) of
    {match, [Inner]} -> Inner;
    _ -> Bin
  end.

%% ---- sessions & workflow events ----

workflow_workspace_dir(SessionRoot0, WorkflowSessionId0) ->
  SessionRoot = ensure_list_str(SessionRoot0),
  WorkflowSessionId = ensure_list_str(WorkflowSessionId0),
  Dir = openagentic_session_store:session_dir(SessionRoot, WorkflowSessionId),
  filename:join([Dir, "workspace"]).

create_step_session(State0, StepId, Role, Attempt) ->
  Root = maps:get(session_root, State0),
  Meta =
    #{
      workflow_id => wf_id(State0),
      step_id => StepId,
      role => Role,
      attempt => Attempt
    },
  {ok, Sid} = openagentic_session_store:create_session(Root, Meta),
  SidBin = to_bin(Sid),
  ok = append_wf_event(Root, Sid, openagentic_events:system_init(SidBin, maps:get(project_dir, State0), #{})),
  Sid.

append_wf_event(State0, Ev) ->
  case maps:get(workflow_event_sink, State0, undefined) of
    F when is_function(F, 1) ->
      F(Ev);
    _ ->
      append_wf_event(maps:get(session_root, State0), maps:get(workflow_session_id, State0), Ev)
  end.

append_wf_event(Root0, Sid0, Ev) ->
  Root = ensure_list_str(Root0),
  Sid = ensure_list_str(Sid0),
  {ok, _Stored} = openagentic_session_store:append_event(Root, Sid, Ev),
  ok.

finalize(State0, Status0, FinalText0) ->
  Status = to_bin(Status0),
  FinalText = to_bin(FinalText0),
  ok =
    append_wf_event(
      State0,
      openagentic_events:workflow_done(wf_id(State0), maps:get(workflow_name, State0, <<>>), Status, FinalText, #{})
    ),
  {ok, #{
    workflow_id => wf_id(State0),
    workflow_name => maps:get(workflow_name, State0, <<>>),
    workflow_session_id => to_bin(maps:get(workflow_session_id, State0)),
    status => Status,
    final_text => FinalText
  }}.

wf_id(State0) ->
  maps:get(workflow_id, State0, <<>>).

%% ---- step defaults ----

step_max_attempts(StepRaw, State0) ->
  StepMax = get_any(StepRaw, [<<"max_attempts">>, max_attempts], undefined),
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  DefMax = get_any(Defaults, [<<"max_attempts">>, max_attempts], 1),
  int_or_default(StepMax, int_or_default(DefMax, 1)).

step_max_steps(StepRaw, State0, Fallback) ->
  StepMax = get_any(StepRaw, [<<"max_steps">>, max_steps], undefined),
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  DefMax = get_any(Defaults, [<<"max_steps">>, max_steps], undefined),
  int_or_default(StepMax, int_or_default(DefMax, int_or_default(Fallback, ?DEFAULT_MAX_STEPS))).

step_timeout_ms(StepRaw, State0) ->
  StepSec = get_any(StepRaw, [<<"timeout_seconds">>, timeout_seconds], undefined),
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  DefSec = get_any(Defaults, [<<"timeout_seconds">>, timeout_seconds], undefined),
  Sec0 = int_or_default(StepSec, int_or_default(DefSec, 600)),
  Sec = clamp_int(Sec0, 1, 3600),
  Sec * 1000.

step_executor_kind(StepRaw) ->
  Exec = to_bin(get_any(StepRaw, [<<"executor">>, executor], <<>>)),
  case Exec of
    <<"fanout_join">> -> <<"fanout_join">>;
    _ -> <<"local_otp">>
  end.

%% ---- file/hash helpers ----

read_workflow_source(ProjectDir0, RelPath0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  RelPath = ensure_list_str(RelPath0),
  case openagentic_fs:resolve_project_path(ProjectDir, RelPath) of
    {ok, Abs} -> file:read_file(Abs);
    {error, unsafe_path} -> {error, unsafe_path}
  end.

sha256_hex(Bin) when is_binary(Bin) ->
  Hash = crypto:hash(sha256, Bin),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Hash]).

new_id() ->
  Bytes = crypto:strong_rand_bytes(16),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

%% ---- generic helpers ----

step_ref(StepRaw, Keys) ->
  V = get_any(StepRaw, Keys, undefined),
  case V of
    null -> null;
    undefined -> null;
    B when is_binary(B) -> string:trim(B);
    L when is_list(L) -> string:trim(iolist_to_binary(L));
    A when is_atom(A) ->
      case A of
        null -> null;
        _ -> atom_to_binary(A, utf8)
      end;
    _ -> null
  end.

put_in(Map0, [K1, K2], V) ->
  M1 = ensure_map(maps:get(K1, Map0, #{})),
  Map0#{K1 := M1#{K2 => V}}.

uniq_bins(L0) ->
  uniq_bins([to_bin(X) || X <- ensure_list_value(L0)], #{}).

uniq_bins([], _Seen) -> [];
uniq_bins([B | Rest], Seen0) ->
  case maps:get(B, Seen0, false) of
    true -> uniq_bins(Rest, Seen0);
    false -> [B | uniq_bins(Rest, Seen0#{B => true})]
  end.

join_bins([], _Sep) -> <<>>;
join_bins([B], _Sep) -> to_bin(B);
join_bins([B | Rest], Sep) -> iolist_to_binary([to_bin(B), Sep, join_bins(Rest, Sep)]).

get_any(Map, Keys, Default) ->
  get_any_loop(ensure_map(Map), Keys, Default).

get_any_loop(_Map, [], Default) -> Default;
get_any_loop(Map, [K | Rest], Default) ->
  case maps:find(K, Map) of
    {ok, V} -> V;
    error -> get_any_loop(Map, Rest, Default)
  end.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

clamp_int(I, Min, Max) when is_integer(I) ->
  erlang:min(Max, erlang:max(Min, I));
clamp_int(_Other, Min, _Max) ->
  Min.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_str(B) when is_binary(B) -> binary_to_list(B);
ensure_list_str(L) when is_list(L) -> L;
ensure_list_str(A) when is_atom(A) -> atom_to_list(A);
ensure_list_str(undefined) -> [];
ensure_list_str(null) -> [];
ensure_list_str(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(_) -> [].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

to_bool_default(V0, Default) ->
  case V0 of
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    <<"1">> -> true;
    <<"0">> -> false;
    1 -> true;
    0 -> false;
    _ -> Default
  end.
