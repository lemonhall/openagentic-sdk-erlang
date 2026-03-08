-module(openagentic_e2e_online_query).
-export([base_runtime_opts/3, run_query/2]).

run_query(Prompt, Opts0) ->
  Ref = make_ref(),
  _ = erlang:put({e2e_events, Ref}, []),
  Sink =
    fun (Ev) ->
      Acc0 = erlang:get({e2e_events, Ref}),
      Acc = case is_list(Acc0) of true -> Acc0; false -> [] end,
      erlang:put({e2e_events, Ref}, [Ev | Acc]),
      ok
    end,
  Opts = (openagentic_e2e_online_utils:ensure_map(Opts0))#{event_sink => Sink},
  Res =
    try
      openagentic_runtime:query(Prompt, Opts)
    catch
      _:T -> {error, {crash, T}}
    end,
  Events0 = erlang:get({e2e_events, Ref}),
  _ = erlang:erase({e2e_events, Ref}),
  Events = lists:reverse(openagentic_e2e_online_utils:ensure_list(Events0)),
  {Res, Events}.

base_runtime_opts(Cfg, TmpProject, Extra0) ->
  Extra = openagentic_e2e_online_utils:ensure_map(Extra0),
  Base = #{
    api_key => maps:get(api_key, Cfg),
    model => maps:get(model, Cfg),
    base_url => maps:get(base_url, Cfg),
    api_key_header => maps:get(api_key_header, Cfg),
    protocol => responses,
    openai_store => maps:get(openai_store, Cfg, true),
    session_root => maps:get(session_root, Cfg),
    cwd => TmpProject,
    project_dir => TmpProject,
    timeout_ms => maps:get(timeout_ms, Cfg, 60000),
    max_steps => 20
  },
  maps:merge(Base, Extra).
