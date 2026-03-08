-module(openagentic_workflow_mgr_tracking).
-export([find_by_monitor/3, is_running/2, maybe_kill_pid/1, maybe_track_runner/5]).

maybe_track_runner(WfSid0, Pid0, SessionRoot0, EngineOpts0, State0) ->
  WfSid = openagentic_workflow_mgr_utils:to_bin(WfSid0),
  SessionRoot = openagentic_workflow_mgr_utils:ensure_list(SessionRoot0),
  EngineOpts = openagentic_workflow_mgr_utils:ensure_map(EngineOpts0),
  case is_pid(Pid0) andalso is_process_alive(Pid0) of
    true ->
      MRef = erlang:monitor(process, Pid0),
      Item0 = openagentic_workflow_mgr_utils:ensure_map(maps:get(WfSid, State0, #{})),
      Now = openagentic_workflow_mgr_utils:now_ms(),
      Item = Item0#{pid => Pid0, mon_ref => MRef, queue => openagentic_workflow_mgr_utils:ensure_list_value(maps:get(queue, Item0, [])), session_root => SessionRoot, engine_opts => EngineOpts, last_progress_ms => maps:get(last_progress_ms, Item0, Now), last_event_type => maps:get(last_event_type, Item0, <<>>)},
      State0#{WfSid => Item};
    false -> State0
  end.

is_running(WfSid0, State0) ->
  WfSid = openagentic_workflow_mgr_utils:to_bin(WfSid0),
  case maps:find(WfSid, State0) of
    {ok, Item} ->
      Pid = maps:get(pid, Item, undefined),
      case is_pid(Pid) andalso is_process_alive(Pid) of true -> {true, Item}; false -> false end;
    error -> false
  end.

find_by_monitor(MRef, Pid, State0) ->
  find_by_monitor_keys(maps:keys(State0), MRef, Pid, State0).

find_by_monitor_keys([], _MRef, _Pid, _State0) -> error;
find_by_monitor_keys([K | Rest], MRef, Pid, State0) ->
  Item = openagentic_workflow_mgr_utils:ensure_map(maps:get(K, State0, #{})),
  case {maps:get(mon_ref, Item, undefined), maps:get(pid, Item, undefined)} of
    {MRef, Pid} -> {ok, K, Item};
    _ -> find_by_monitor_keys(Rest, MRef, Pid, State0)
  end.

maybe_kill_pid(Pid) when is_pid(Pid) -> catch exit(Pid, kill), ok;
maybe_kill_pid(_Other) -> ok.
