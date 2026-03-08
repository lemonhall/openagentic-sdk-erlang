-module(openagentic_case_scheduler_state_refresh).
-export([apply_config/3, init_state/1, scan_opts/1, tick_ms/2]).

init_state(DefaultTickMs) ->
  #{enabled => false, session_root => undefined, runtime_opts => #{}, tick_ms => DefaultTickMs}.

apply_config(Opts0, State0, DefaultTickMs) ->
  Opts = openagentic_case_scheduler_utils:ensure_map(Opts0),
  SessionRoot = openagentic_case_scheduler_utils:ensure_list(maps:get(session_root, Opts, maps:get(sessionRoot, Opts, undefined))),
  TickMs = openagentic_case_scheduler_utils:int_or_default(maps:get(case_scheduler_tick_ms, Opts, maps:get(caseSchedulerTickMs, Opts, DefaultTickMs)), DefaultTickMs),
  RuntimeOpts = maps:without([web_bind, web_port, bind, port, project_dir, session_root, sessionRoot, case_scheduler_tick_ms, caseSchedulerTickMs], Opts),
  State0#{enabled => SessionRoot =/= [] andalso SessionRoot =/= "undefined", session_root => SessionRoot, runtime_opts => RuntimeOpts, tick_ms => TickMs}.

tick_ms(State0, DefaultTickMs) ->
  maps:get(tick_ms, State0, DefaultTickMs).

scan_opts(State0) ->
  #{session_root => maps:get(session_root, State0, undefined), runtime_opts => maps:get(runtime_opts, State0, #{})}.
