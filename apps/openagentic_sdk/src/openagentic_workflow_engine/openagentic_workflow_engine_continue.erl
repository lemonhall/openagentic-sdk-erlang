-module(openagentic_workflow_engine_continue).
-export([continue/4,continue_start/4,init_continue/4]).

continue(SessionRoot0, WorkflowSessionId0, Message0, Opts0) ->
  SessionRoot = openagentic_workflow_engine_utils:ensure_list_str(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_engine_utils:ensure_list_str(WorkflowSessionId0),
  Message = openagentic_workflow_engine_utils:to_bin(Message0),
  Opts = openagentic_workflow_engine_utils:ensure_map(Opts0),
  case init_continue(SessionRoot, WorkflowSessionId, Message, Opts) of
    {ok, StartStepId, State0} ->
      openagentic_workflow_engine_execution:execute(StartStepId, State0);
    Err ->
      Err
  end.

%% Continue an existing workflow session asynchronously.

continue_start(SessionRoot0, WorkflowSessionId0, Message0, Opts0) ->
  SessionRoot = openagentic_workflow_engine_utils:ensure_list_str(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_engine_utils:ensure_list_str(WorkflowSessionId0),
  Message = openagentic_workflow_engine_utils:to_bin(Message0),
  Opts = openagentic_workflow_engine_utils:ensure_map(Opts0),
  case init_continue(SessionRoot, WorkflowSessionId, Message, Opts) of
    {ok, StartStepId, State0} ->
      Pid =
        spawn(
          fun () ->
            _ = openagentic_workflow_engine_execution:execute(StartStepId, State0),
            ok
          end
        ),
      {ok, #{
        pid => Pid,
        workflow_id => openagentic_workflow_engine_state:wf_id(State0),
        workflow_name => maps:get(workflow_name, State0, <<>>),
        workflow_session_id => openagentic_workflow_engine_utils:to_bin(maps:get(workflow_session_id, State0, <<>>))
      }};
    Err ->
      Err
  end.

init_continue(SessionRoot, WorkflowSessionId, Message, Opts0) ->
  %% Read existing workflow session to recover workflow.init context.
  Events = openagentic_session_store:read_events(SessionRoot, WorkflowSessionId),
  case openagentic_workflow_engine_history_time:find_workflow_init(Events) of
    {error, _} = Err ->
      Err;
    {ok, Init} ->
      WfId = maps:get(<<"workflow_id">>, Init, maps:get(workflow_id, Init, <<>>)),
      WfName = maps:get(<<"workflow_name">>, Init, maps:get(workflow_name, Init, <<>>)),
      DslPath = openagentic_workflow_engine_utils:to_bin(maps:get(<<"dsl_path">>, Init, maps:get(dsl_path, Init, <<"workflows/three-provinces-six-ministries.v1.json">>))),
      ProjectDir0 = maps:get(<<"project_dir">>, Init, maps:get(project_dir, Init, maps:get(<<"projectDir">>, Init, maps:get(projectDir, Init, <<".">>)))),
      ProjectDir = openagentic_workflow_engine_utils:ensure_list_str(ProjectDir0),

      %% Collect original controller_input + any prior followups + this message.
      BaseInput = openagentic_workflow_engine_utils:to_bin(maps:get(<<"controller_input">>, Init, maps:get(controller_input, Init, <<>>))),
      Followups = [openagentic_workflow_engine_utils:to_bin(maps:get(<<"text">>, E, maps:get(text, E, <<>>))) || E <- Events, openagentic_workflow_engine_history_time:is_controller_message(E)],
      ControllerInput =
        iolist_to_binary([
          BaseInput,
          <<"\n\n---\n\n# Followup\n\n">>,
          openagentic_workflow_engine_utils:join_bins([X || X <- Followups, byte_size(string:trim(X)) > 0] ++ [Message], <<"\n\n">>),
          <<"\n">>
        ]),

      %% Reconstruct last outputs/failures so resuming a failed step can bind inputs and show guard reasons.
      StepOutputsAll = openagentic_workflow_engine_history_time:reconstruct_step_outputs(Events),
      StepFailuresAll = openagentic_workflow_engine_history_time:reconstruct_step_failures(Events),
      StepAttempts = #{},

      ExplicitTimeContext = openagentic_time_context:from_opts(Opts0),
      WfWorkspaceDir = openagentic_workflow_engine_state:workflow_workspace_dir(SessionRoot, WorkflowSessionId),
      ok = filelib:ensure_dir(filename:join([WfWorkspaceDir, "x"])),
      case openagentic_workflow_dsl:load_and_validate(ProjectDir, openagentic_workflow_engine_utils:ensure_list_str(DslPath), Opts0) of
        {ok, Wf} ->
          Defaults = openagentic_workflow_engine_utils:ensure_map(maps:get(<<"defaults">>, Wf, #{})),
          StepsById = openagentic_workflow_engine_utils:ensure_map(maps:get(<<"steps_by_id">>, Wf, #{})),
          StartDefault = maps:get(<<"start_step_id">>, Wf, <<>>),
          StartStepId = openagentic_workflow_engine_history_steps:pick_continue_step(Events, openagentic_workflow_engine_utils:to_bin(StartDefault)),
          {PrevStatus, _PrevDoneIdx} = openagentic_workflow_engine_history_steps:last_workflow_done(openagentic_workflow_engine_utils:ensure_list_value(Events)),
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
                  false -> openagentic_workflow_engine_history_time:recover_workflow_time_context(Events, Init, Opts0)
                end;
              Ctx -> Ctx
            end,
          Opts1 = openagentic_time_context:put_in_opts(Opts0, TimeContext),
          Opts = openagentic_workflow_engine_execution:ensure_web_answerer(Opts1, openagentic_workflow_engine_utils:to_bin(WorkflowSessionId)),
          State0 =
            #{
              project_dir => ProjectDir,
              session_root => SessionRoot,
              workflow_id => WfId,
              workflow_name => WfName,
              workflow_session_id => WorkflowSessionId,
              workspace_dir => WfWorkspaceDir,
              workflow_rel_path => openagentic_workflow_engine_utils:to_bin(DslPath),
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
          ok = openagentic_workflow_engine_state:append_wf_event(State0, #{type => <<"workflow.controller.message">>, workflow_id => openagentic_workflow_engine_utils:to_bin(WfId), text => Message}),
          ok = openagentic_workflow_engine_state:append_wf_event(State0, #{type => <<"workflow.run.start">>, workflow_id => openagentic_workflow_engine_utils:to_bin(WfId), start_step_id => StartStepId, time_context => TimeContext}),
          {ok, StartStepId, State0};
        Err ->
          Err
      end
  end.
