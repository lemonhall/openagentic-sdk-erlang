-module(openagentic_workflow_mgr_calls).
-export([handle_call/3]).

handle_call({start_workflow, ProjectDir, WorkflowRelPath, Prompt, EngineOpts0}, _From, State0) ->
  EngineOpts = openagentic_workflow_mgr_utils:ensure_map(EngineOpts0),
  case openagentic_workflow_engine:start(ProjectDir, WorkflowRelPath, Prompt, EngineOpts) of
    {ok, Info} ->
      WfSid = openagentic_workflow_mgr_utils:to_bin(maps:get(workflow_session_id, Info, <<>>)),
      Pid = maps:get(pid, Info, undefined),
      State1 = openagentic_workflow_mgr_tracking:maybe_track_runner(WfSid, Pid, openagentic_workflow_mgr_utils:ensure_list(openagentic_workflow_mgr_status:session_root_from_opts(EngineOpts)), EngineOpts, State0),
      {reply, {ok, Info#{queued => false, queue_length => 0, status => <<"running">>, resumed_from_stalled => false}}, State1};
    Err -> {reply, Err, State0}
  end;
handle_call({continue_workflow, SessionRoot0, WorkflowSessionId0, Message0, EngineOpts0}, _From, State0) ->
  SessionRoot = openagentic_workflow_mgr_utils:ensure_list(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_mgr_utils:to_bin(WorkflowSessionId0),
  Message = openagentic_workflow_mgr_utils:to_bin(Message0),
  EngineOpts = openagentic_workflow_mgr_utils:ensure_map(EngineOpts0),
  case openagentic_workflow_mgr_tracking:is_running(WorkflowSessionId, State0) of
    {true, Item0} ->
      Q0 = openagentic_workflow_mgr_utils:ensure_list_value(maps:get(queue, Item0, [])),
      Q = Q0 ++ [Message],
      Item = Item0#{queue := Q, session_root := SessionRoot, engine_opts := EngineOpts},
      {reply, {ok, #{queued => true, queue_length => length(Q), status => <<"queued">>, resumed_from_stalled => false}}, State0#{WorkflowSessionId => Item}};
    false ->
      PreviousStatus = openagentic_workflow_mgr_status:session_terminal_status(SessionRoot, WorkflowSessionId),
      case openagentic_workflow_engine:continue_start(SessionRoot, openagentic_workflow_mgr_utils:ensure_list(WorkflowSessionId), Message, EngineOpts) of
        {ok, Info} ->
          Pid = maps:get(pid, Info, undefined),
          State1 = openagentic_workflow_mgr_tracking:maybe_track_runner(WorkflowSessionId, Pid, SessionRoot, EngineOpts, State0),
          ResumedFromStalled = PreviousStatus =:= <<"stalled">>,
          Status = case ResumedFromStalled of true -> <<"resumed_from_stalled">>; false -> <<"running">> end,
          Reply0 = Info#{queued => false, queue_length => 0, status => Status, resumed_from_stalled => ResumedFromStalled},
          Reply = case PreviousStatus of undefined -> Reply0; <<>> -> Reply0; _ -> Reply0#{previous_status => PreviousStatus} end,
          {reply, {ok, Reply}, State1};
        Err -> {reply, Err, State0}
      end
  end;
handle_call({cancel_workflow, SessionRoot0, WorkflowSessionId0}, _From, State0) ->
  _SessionRoot = openagentic_workflow_mgr_utils:ensure_list(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_mgr_utils:to_bin(WorkflowSessionId0),
  case maps:find(WorkflowSessionId, State0) of
    {ok, Item0} ->
      _ = openagentic_workflow_mgr_tracking:maybe_kill_pid(maps:get(pid, Item0, undefined)),
      {reply, {ok, #{ok => true, canceled => true}}, maps:remove(WorkflowSessionId, State0)};
    error -> {reply, {ok, #{ok => true, canceled => false}}, State0}
  end;
handle_call({status, SessionRoot0, WorkflowSessionId0}, _From, State0) ->
  WorkflowSessionId = openagentic_workflow_mgr_utils:to_bin(WorkflowSessionId0),
  case openagentic_workflow_mgr_tracking:is_running(WorkflowSessionId, State0) of
    {true, Item} ->
      QueueLength = length(openagentic_workflow_mgr_utils:ensure_list_value(maps:get(queue, Item, []))),
      Status = case QueueLength > 0 of true -> <<"queued">>; false -> <<"running">> end,
      {reply, {ok, #{running => true, queue_length => QueueLength, status => Status}}, State0};
    false ->
      Reply0 = #{running => false, queue_length => 0},
      Reply = maps:merge(Reply0, openagentic_workflow_mgr_status:session_status_info(SessionRoot0, WorkflowSessionId)),
      {reply, {ok, Reply}, State0}
  end;
handle_call(_Other, _From, State0) ->
  {reply, {error, unsupported}, State0}.
