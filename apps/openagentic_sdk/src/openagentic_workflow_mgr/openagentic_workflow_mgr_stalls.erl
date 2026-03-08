-module(openagentic_workflow_mgr_stalls).
-export([check_stalls/2, idle_timeout_ms/1]).

-define(DEFAULT_IDLE_TIMEOUT_MS, 300 * 1000).
-define(DEFAULT_QUESTION_TIMEOUT_MS, 10 * 60 * 1000).

check_stalls(Now, State0) ->
  check_stalls_keys(maps:keys(State0), Now, State0).

check_stalls_keys([], _Now, State0) -> State0;
check_stalls_keys([WfSid | Rest], Now, State0) ->
  Item0 = openagentic_workflow_mgr_utils:ensure_map(maps:get(WfSid, State0, #{})),
  Pid = maps:get(pid, Item0, undefined),
  case is_pid(Pid) andalso is_process_alive(Pid) of
    false -> check_stalls_keys(Rest, Now, maps:remove(WfSid, State0));
    true ->
      Last = maps:get(last_progress_ms, Item0, Now),
      EvType = openagentic_workflow_mgr_utils:to_bin(maps:get(last_event_type, Item0, <<>>)),
      EngineOpts = openagentic_workflow_mgr_utils:ensure_map(maps:get(engine_opts, Item0, #{})),
      TimeoutMs = case EvType of <<"user.question">> -> question_timeout_ms(EngineOpts); _ -> idle_timeout_ms(EngineOpts) end,
      case (Now - Last) > TimeoutMs of
        true ->
          SessionRoot = openagentic_workflow_mgr_utils:ensure_list(maps:get(session_root, Item0, "")),
          _ = openagentic_workflow_mgr_tracking:maybe_kill_pid(Pid),
          _ = append_stalled_done(SessionRoot, WfSid, EvType, TimeoutMs),
          check_stalls_keys(Rest, Now, maps:remove(WfSid, State0));
        false -> check_stalls_keys(Rest, Now, State0)
      end
  end.

idle_timeout_ms(EngineOpts0) ->
  EngineOpts = openagentic_workflow_mgr_utils:ensure_map(EngineOpts0),
  Sec0 = maps:get(idle_timeout_seconds, EngineOpts, maps:get(<<"idle_timeout_seconds">>, EngineOpts, undefined)),
  Sec = openagentic_workflow_mgr_utils:int_or_default(Sec0, ?DEFAULT_IDLE_TIMEOUT_MS div 1000),
  openagentic_workflow_mgr_utils:clamp_int(Sec, 5, 3600) * 1000.

question_timeout_ms(EngineOpts0) ->
  EngineOpts = openagentic_workflow_mgr_utils:ensure_map(EngineOpts0),
  Sec0 = maps:get(question_timeout_seconds, EngineOpts, maps:get(<<"question_timeout_seconds">>, EngineOpts, ?DEFAULT_QUESTION_TIMEOUT_MS div 1000)),
  Sec = openagentic_workflow_mgr_utils:int_or_default(Sec0, ?DEFAULT_QUESTION_TIMEOUT_MS div 1000),
  openagentic_workflow_mgr_utils:clamp_int(Sec, 30, 3600) * 1000.

append_stalled_done(SessionRoot0, WorkflowSessionId0, LastEventType0, TimeoutMs0) ->
  SessionRoot = openagentic_workflow_mgr_utils:ensure_list(SessionRoot0),
  WfSid = openagentic_workflow_mgr_utils:ensure_list(WorkflowSessionId0),
  MetaPath = filename:join([openagentic_session_store:session_dir(SessionRoot, WfSid), "meta.json"]),
  {WfId, WfName} =
    case file:read_file(MetaPath) of
      {ok, Bin} ->
        case catch openagentic_json:decode(Bin) of
          M when is_map(M) ->
            Md = openagentic_workflow_mgr_utils:ensure_map(maps:get(<<"metadata">>, M, maps:get(metadata, M, #{}))),
            {openagentic_workflow_mgr_utils:to_bin(maps:get(<<"workflow_id">>, Md, maps:get(workflow_id, Md, <<>>))), openagentic_workflow_mgr_utils:to_bin(maps:get(<<"workflow_name">>, Md, maps:get(workflow_name, Md, <<>>)))};
          _ -> {<<>>, <<>>}
        end;
      _ -> {<<>>, <<>>}
    end,
  LastEventType = openagentic_workflow_mgr_utils:to_bin(LastEventType0),
  TimeoutMs = openagentic_workflow_mgr_utils:int_or_default(TimeoutMs0, ?DEFAULT_IDLE_TIMEOUT_MS),
  Msg = iolist_to_binary([<<"Watchdog: no new events for ">>, integer_to_binary(TimeoutMs), <<"ms (last_event_type=">>, LastEventType, <<"). Runner was cancelled; you can continue in-place or start a new run.">>]),
  Ev = openagentic_events:workflow_done(WfId, WfName, <<"stalled">>, Msg, #{by => <<"watchdog">>}),
  _ = openagentic_session_store:append_event(SessionRoot, WfSid, Ev),
  ok.
