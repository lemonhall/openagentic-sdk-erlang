-module(openagentic_task_runners_builtin).

-export([built_in_explore/1, built_in_research/1]).

built_in_explore(BaseOpts0) ->
  built_in_runner(
    BaseOpts0,
    <<"explore">>,
    [<<"Read">>, <<"List">>, <<"Glob">>, <<"Grep">>],
    [openagentic_tool_read, openagentic_tool_list, openagentic_tool_glob, openagentic_tool_grep],
    openagentic_built_in_subagents:explore_system_prompt(),
    explore_task_failed
  ).

built_in_research(BaseOpts0) ->
  built_in_runner(
    BaseOpts0,
    <<"research">>,
    [<<"WebSearch">>, <<"WebFetch">>],
    [openagentic_tool_websearch, openagentic_tool_webfetch],
    openagentic_built_in_subagents:research_system_prompt(),
    research_task_failed
  ).

built_in_runner(BaseOpts0, ExpectedAgent, AllowedTools, ToolMods, SystemPrompt, FailureTag) ->
  BaseOpts = openagentic_task_runners_utils:ensure_map(BaseOpts0),
  MaxSteps = maps:get(subagent_max_steps, BaseOpts, maps:get(subagentMaxSteps, BaseOpts, 25)),
  fun (Agent0, Prompt0, TaskCtx0) ->
    Agent = ensure_agent(Agent0, ExpectedAgent),
    Prompt = string:trim(openagentic_task_runners_utils:to_bin(Prompt0)),
    TaskCtx = openagentic_task_runners_utils:ensure_map(TaskCtx0),
    ParentSessionId = openagentic_task_runners_utils:to_bin(maps:get(session_id, TaskCtx, <<>>)),
    ParentToolUseId = openagentic_task_runners_utils:to_bin(maps:get(tool_use_id, TaskCtx, <<>>)),
    Emit = maps:get(emit_progress, TaskCtx, undefined),
    _ = openagentic_task_runners_progress:maybe_emit(Emit, status_message(Agent, <<"启动">>)),
    SubOpts = build_sub_opts(BaseOpts, AllowedTools, ToolMods, SystemPrompt, MaxSteps, Agent, Emit),
    case openagentic_runtime:query(Prompt, SubOpts) of
      {ok, #{session_id := SubSessionId0, final_text := FinalText0}} ->
        #{<<"ok">> => true, <<"agent">> => Agent, <<"parent_session_id">> => ParentSessionId, <<"parent_tool_use_id">> => ParentToolUseId, <<"sub_session_id">> => openagentic_task_runners_utils:to_bin(SubSessionId0), <<"answer">> => string:trim(openagentic_task_runners_utils:to_bin(FinalText0))};
      {error, Reason} ->
        _ = openagentic_task_runners_progress:maybe_emit(Emit, status_message(Agent, <<"运行错误">>)),
        erlang:error({FailureTag, Reason})
    end
  end.

ensure_agent(Agent0, ExpectedAgent) ->
  Agent = string:lowercase(string:trim(openagentic_task_runners_utils:to_bin(Agent0))),
  case Agent of ExpectedAgent -> Agent; _ -> erlang:error({unhandled_agent, Agent}) end.

build_sub_opts(BaseOpts, AllowedTools, ToolMods, SystemPrompt, MaxSteps, Agent, Emit) ->
  SubOpts0 = maps:merge(BaseOpts, #{tools => ToolMods, allowed_tools => AllowedTools, permission_gate => openagentic_permissions:bypass(), task_runner => undefined, task_agents => [], resume_session_id => undefined, resumeSessionId => undefined, include_partial_messages => false, max_steps => MaxSteps, system_prompt => SystemPrompt}),
  SubOpts0#{event_sink => openagentic_task_runners_progress:sub_event_sink(Agent, Emit)}.

status_message(Agent, Suffix) ->
  iolist_to_binary([<<"子任务(">>, Agent, <<")：">>, Suffix]).
