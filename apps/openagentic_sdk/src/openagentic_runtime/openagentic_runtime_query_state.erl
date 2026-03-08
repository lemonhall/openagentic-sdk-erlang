-module(openagentic_runtime_query_state).
-export([resolve_resume_state/1,init_query_state/1]).
resolve_resume_state(QueryCtx) ->
  Resume = maps:get(resume, QueryCtx, <<>>),
  RootDir = maps:get(root, QueryCtx),
  ResumeMaxEvents = maps:get(resume_max_events, QueryCtx, 1000),
  ResumeMaxBytes = maps:get(resume_max_bytes, QueryCtx, 2000000),
  Metadata = maps:get(metadata, QueryCtx, #{}),
  case byte_size(Resume) > 0 of
    true ->
      try
        _ = openagentic_session_store:session_dir(RootDir, Resume),
        Past0 = openagentic_session_store:read_events(RootDir, Resume),
        Past = openagentic_runtime_resume:trim_events_for_resume(Past0, ResumeMaxEvents, ResumeMaxBytes),
        Prev = openagentic_runtime_resume:infer_previous_response_id(Past),
        {ok, QueryCtx#{session_id => Resume, past_events => Past, previous_response_id => Prev}}
      catch
        _:_ -> {error, {invalid_session_id, Resume}}
      end;
    false ->
      {ok, Sid} = openagentic_session_store:create_session(RootDir, Metadata),
      {ok, QueryCtx#{session_id => Sid, past_events => [], previous_response_id => undefined}}
  end.
init_query_state(QueryCtx) ->
  RootDir = maps:get(root, QueryCtx),
  SessionId = maps:get(session_id, QueryCtx),
  WorkspaceDir0 = openagentic_runtime_paths:ensure_workspace_dir(RootDir, SessionId, maps:get(workspace_dir_opt, QueryCtx, undefined)),
  ok = filelib:ensure_dir(filename:join([WorkspaceDir0, "x"])),
  State0 = #{root => RootDir, session_id => SessionId, events => maps:get(past_events, QueryCtx, []), event_sink => maps:get(event_sink, QueryCtx, undefined), project_dir => maps:get(project_dir, QueryCtx), workspace_dir => WorkspaceDir0, api_key => maps:get(api_key, QueryCtx, undefined), model => maps:get(model, QueryCtx, undefined), base_url => maps:get(base_url, QueryCtx, undefined), timeout_ms => maps:get(timeout_ms, QueryCtx), provider_mod => maps:get(provider_mod, QueryCtx), provider_retry => maps:get(provider_retry, QueryCtx, #{}), include_partial_messages => maps:get(include_partial_messages, QueryCtx, false), openai_store => maps:get(openai_store, QueryCtx, true), api_key_header => maps:get(api_key_header, QueryCtx, undefined), resume_max_events => maps:get(resume_max_events, QueryCtx, 1000), resume_max_bytes => maps:get(resume_max_bytes, QueryCtx, 2000000), compaction => maps:get(compaction, QueryCtx, #{}), protocol => maps:get(protocol, QueryCtx), system_prompt => maps:get(system_prompt, QueryCtx, <<>>), time_context => maps:get(time_context, QueryCtx), tool_schemas => maps:get(tool_schemas, QueryCtx, []), registry => maps:get(registry, QueryCtx), permission_gate => maps:get(permission_gate, QueryCtx, undefined), allowed_tools => maps:get(allowed_tools, QueryCtx, undefined), user_answerer => maps:get(user_answerer, QueryCtx, undefined), task_progress_emitter => maps:get(task_progress_emitter, QueryCtx, undefined), task_runner => maps:get(task_runner, QueryCtx, undefined), hook_engine => maps:get(hook_engine, QueryCtx, #{}), tool_output_artifacts => maps:get(tool_output_artifacts, QueryCtx, #{}), task_agents => maps:get(task_agents, QueryCtx, []), previous_response_id => maps:get(previous_response_id, QueryCtx, undefined), supports_previous_response_id => maps:get(supports_previous_response_id, QueryCtx, false), steps => 0, max_steps => maps:get(max_steps, QueryCtx, 50)},
  State1 = case byte_size(maps:get(resume, QueryCtx, <<>>)) > 0 of true -> State0; false -> openagentic_runtime_events:append_event(State0, openagentic_events:system_init(SessionId, maps:get(cwd, QueryCtx), #{time_context => maps:get(time_context, QueryCtx)})) end,
  openagentic_runtime_events:append_event(State1, openagentic_events:user_message(maps:get(prompt, QueryCtx))).
