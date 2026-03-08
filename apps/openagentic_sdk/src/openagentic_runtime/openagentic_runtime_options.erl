-module(openagentic_runtime_options).
-export([build_provider_opts/3,auto_task_runner/2,maybe_add_built_in_runner/4,pick_opt/2,to_bool_default/2,is_tool_allowed/2,default_tools/0]).
-define(DEFAULT_TIMEOUT_MS, 60000).

build_provider_opts(State, InputItems, ToolSchemas) ->
  Protocol = maps:get(protocol, State, responses),
  StoreFlag = maps:get(openai_store, State, true),
  ApiKeyHeader0 = maps:get(api_key_header, State, undefined),
  BaseUrl0 = maps:get(base_url, State, undefined),
  OptsA = #{
    api_key => maps:get(api_key, State, <<"">>),
    model => maps:get(model, State, <<"">>),
    timeout_ms => maps:get(timeout_ms, State, ?DEFAULT_TIMEOUT_MS),
    input => InputItems,
    tools => ToolSchemas
  },
  Opts0 =
    case BaseUrl0 of
      undefined -> OptsA;
      null -> OptsA;
      <<>> -> OptsA;
      "" -> OptsA;
      <<"undefined">> -> OptsA;
      VUrl -> OptsA#{base_url => VUrl}
    end,
  Opts1 =
    case Protocol of
      responses -> Opts0#{store => StoreFlag};
      _ -> Opts0
    end,
  case ApiKeyHeader0 of
    undefined -> Opts1;
    null -> Opts1;
    <<>> -> Opts1;
    "" -> Opts1;
    VHdr -> Opts1#{api_key_header => VHdr}
  end.

auto_task_runner(TaskAgents0, Opts) ->
  TaskAgents = openagentic_task_agents:normalize(TaskAgents0),
  Runners0 =
    [
      maybe_add_built_in_runner(<<"explore">>, fun openagentic_task_runners:built_in_explore/1, TaskAgents, Opts),
      maybe_add_built_in_runner(<<"research">>, fun openagentic_task_runners:built_in_research/1, TaskAgents, Opts)
    ],
  Runners = [R || R <- Runners0, R =/= undefined],
  case Runners of
    [] -> undefined;
    [Runner] -> Runner;
    _ -> openagentic_task_runners:compose(Runners)
  end.

maybe_add_built_in_runner(Name, Builder, TaskAgents, Opts) ->
  case openagentic_task_agents:has_agent(Name, TaskAgents) of
    true -> Builder(Opts);
    false -> undefined
  end.

pick_opt(_Map, []) ->
  undefined;
pick_opt(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_opt(Map, Rest);
    V -> V
  end.

to_bool_default(undefined, Default) -> Default;
to_bool_default(null, Default) -> Default;
to_bool_default(true, _Default) -> true;
to_bool_default(false, _Default) -> false;
to_bool_default(1, _Default) -> true;
to_bool_default(0, _Default) -> false;
to_bool_default(V, Default) ->
  S = string:lowercase(string:trim(openagentic_runtime_utils:to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"allow">> -> true;
    <<"ok">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.

is_tool_allowed(undefined, _ToolName) ->
  true;
is_tool_allowed(Allowed, ToolName0) when is_list(Allowed) ->
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  lists:member(ToolName, [openagentic_runtime_utils:to_bin(X) || X <- Allowed]);
is_tool_allowed(_Other, _ToolName) ->
  true.

default_tools() ->
  [
    openagentic_tool_ask_user_question,
    openagentic_tool_read,
    openagentic_tool_list,
    openagentic_tool_write,
    openagentic_tool_edit,
    openagentic_tool_glob,
    openagentic_tool_grep,
    openagentic_tool_bash,
    openagentic_tool_webfetch,
    openagentic_tool_websearch,
    openagentic_tool_skill,
    openagentic_tool_slash_command,
    openagentic_tool_notebook_edit,
    openagentic_tool_lsp,
    openagentic_tool_todo_write,
    openagentic_tool_task
  ].
