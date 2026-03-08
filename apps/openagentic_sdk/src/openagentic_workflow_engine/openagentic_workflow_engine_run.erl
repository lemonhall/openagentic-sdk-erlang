-module(openagentic_workflow_engine_run).
-export([run/4,start/4,init_run/5]).

run(ProjectDir0, WorkflowRelPath0, ControllerInput0, Opts0) ->
  ProjectDir = openagentic_workflow_engine_utils:ensure_list_str(ProjectDir0),
  WorkflowRelPath = openagentic_workflow_engine_utils:ensure_list_str(WorkflowRelPath0),
  ControllerInput = openagentic_workflow_engine_utils:to_bin(ControllerInput0),
  Opts = openagentic_workflow_engine_utils:ensure_map(Opts0),
  SessionRoot = openagentic_workflow_engine_utils:ensure_list_str(maps:get(session_root, Opts, openagentic_paths:default_session_root())),

  case init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) of
    {ok, Start, State0} ->
      openagentic_workflow_engine_execution:execute(Start, State0);
    Err ->
      Err
  end.

%% Start a workflow asynchronously (returns ids immediately).
%% The workflow continues in a spawned process and writes events to workflow session.

start(ProjectDir0, WorkflowRelPath0, ControllerInput0, Opts0) ->
  ProjectDir = openagentic_workflow_engine_utils:ensure_list_str(ProjectDir0),
  WorkflowRelPath = openagentic_workflow_engine_utils:ensure_list_str(WorkflowRelPath0),
  ControllerInput = openagentic_workflow_engine_utils:to_bin(ControllerInput0),
  Opts = openagentic_workflow_engine_utils:ensure_map(Opts0),
  SessionRoot = openagentic_workflow_engine_utils:ensure_list_str(maps:get(session_root, Opts, openagentic_paths:default_session_root())),
  case init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) of
    {ok, Start, State0} ->
      Pid =
        spawn(
          fun () ->
            _ = openagentic_workflow_engine_execution:execute(Start, State0),
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

%% Continue an existing workflow session by re-running (sync) from the last relevant step.
%% Keeps the same workflow_session_id and appends events to it.

init_run(ProjectDir, WorkflowRelPath, ControllerInput, SessionRoot, Opts) ->
  TimeContext = openagentic_time_context:resolve(Opts),
  Opts1 = openagentic_time_context:put_in_opts(Opts, TimeContext),
  case openagentic_workflow_dsl:load_and_validate(ProjectDir, WorkflowRelPath, Opts1) of
    {ok, Wf} ->
      case openagentic_workflow_engine_utils:read_workflow_source(ProjectDir, WorkflowRelPath) of
        {ok, SrcBin} ->
          DslHash = openagentic_workflow_engine_utils:sha256_hex(SrcBin),
          WfName = maps:get(<<"name">>, Wf, <<>>),
          WorkflowId = openagentic_workflow_engine_utils:new_id(),
          {ok, WfSessionId0} =
            openagentic_session_store:create_session(SessionRoot, #{
              workflow_id => WorkflowId,
              workflow_name => WfName,
              dsl_path => openagentic_workflow_engine_utils:to_bin(WorkflowRelPath),
              dsl_sha256 => DslHash,
              time_context => TimeContext
            }),
           WfSessionId = openagentic_workflow_engine_utils:to_bin(WfSessionId0),
           Opts2 = openagentic_workflow_engine_execution:ensure_web_answerer(Opts1, WfSessionId),
           WfWorkspaceDir = openagentic_workflow_engine_state:workflow_workspace_dir(SessionRoot, WfSessionId0),
           ok = filelib:ensure_dir(filename:join([WfWorkspaceDir, "x"])),
           ok = openagentic_workflow_engine_state:append_wf_event(SessionRoot, WfSessionId0, openagentic_events:system_init(WfSessionId, ProjectDir, #{time_context => TimeContext})),
           ok =
             openagentic_workflow_engine_state:append_wf_event(
               SessionRoot,
               WfSessionId0,
              openagentic_events:workflow_init(
                WorkflowId,
                WfName,
                WorkflowRelPath,
                DslHash,
                #{project_dir => openagentic_workflow_engine_utils:to_bin(ProjectDir), controller_input => ControllerInput, time_context => TimeContext}
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
               workflow_rel_path => openagentic_workflow_engine_utils:to_bin(WorkflowRelPath),
               defaults => openagentic_workflow_engine_utils:ensure_map(maps:get(<<"defaults">>, Wf, #{})),
               steps_by_id => openagentic_workflow_engine_utils:ensure_map(maps:get(<<"steps_by_id">>, Wf, #{})),
               controller_input => ControllerInput,
              time_context => TimeContext,
              step_outputs => #{},
              step_attempts => #{},
              step_failures => #{},
              opts => Opts2
            },
          Start = maps:get(<<"start_step_id">>, Wf, <<>>),
          ok = openagentic_workflow_engine_state:append_wf_event(State0, #{type => <<"workflow.run.start">>, workflow_id => openagentic_workflow_engine_utils:to_bin(WorkflowId), start_step_id => openagentic_workflow_engine_utils:to_bin(Start), time_context => TimeContext}),
          {ok, openagentic_workflow_engine_utils:to_bin(Start), State0};
        {error, Reason} ->
          {error, Reason}
      end;
    Err ->
      Err
  end.
