-module(openagentic_workflow_mgr_status).
-export([event_progress_type/1, session_root_from_opts/1, session_status_info/2, session_terminal_status/2]).

session_status_info(undefined, _WorkflowSessionId) -> #{};
session_status_info(SessionRoot0, WorkflowSessionId0) ->
  SessionRoot = openagentic_workflow_mgr_utils:ensure_list(SessionRoot0),
  WorkflowSessionId = openagentic_workflow_mgr_utils:ensure_list(WorkflowSessionId0),
  case find_last_workflow_done(openagentic_session_store:read_events(SessionRoot, WorkflowSessionId)) of
    false -> #{};
    Ev0 ->
      Ev = openagentic_workflow_mgr_utils:ensure_map(Ev0),
      Base = #{status => openagentic_workflow_mgr_utils:to_bin(maps:get(<<"status">>, Ev, maps:get(status, Ev, <<>>)))},
      case maps:get(<<"by">>, Ev, maps:get(by, Ev, undefined)) of undefined -> Base; By -> Base#{by => openagentic_workflow_mgr_utils:to_bin(By)} end
  end.

session_terminal_status(SessionRoot, WorkflowSessionId) ->
  case session_status_info(SessionRoot, WorkflowSessionId) of #{status := Status} -> Status; _ -> undefined end.

find_last_workflow_done(Events0) ->
  lists:foldl(
    fun (Ev0, Best0) ->
      Ev = openagentic_workflow_mgr_utils:ensure_map(Ev0),
      case maps:get(<<"type">>, Ev, maps:get(type, Ev, <<>>)) of <<"workflow.done">> -> Ev; _ -> Best0 end
    end,
    false,
    openagentic_workflow_mgr_utils:ensure_list_value(Events0)
  ).

session_root_from_opts(Opts0) ->
  Opts = openagentic_workflow_mgr_utils:ensure_map(Opts0),
  case maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined)) of undefined -> openagentic_paths:default_session_root(); V -> V end.

event_progress_type(Ev0) ->
  Ev = openagentic_workflow_mgr_utils:ensure_map(Ev0),
  EvType = openagentic_workflow_mgr_utils:to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))),
  case EvType of
    <<"workflow.step.event">> ->
      StepEv = openagentic_workflow_mgr_utils:ensure_map(maps:get(step_event, Ev, maps:get(<<"step_event">>, Ev, #{}))),
      case openagentic_workflow_mgr_utils:to_bin(maps:get(type, StepEv, maps:get(<<"type">>, StepEv, <<>>))) of <<>> -> EvType; StepType -> StepType end;
    _ -> EvType
  end.
