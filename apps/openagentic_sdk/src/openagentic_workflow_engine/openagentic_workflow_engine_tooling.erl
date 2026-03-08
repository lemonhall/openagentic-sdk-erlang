-module(openagentic_workflow_engine_tooling).
-export([role_system_prompt/3,tool_policy_for_step/2,ensure_ask_user/1,all_known_tool_names/0]).

role_system_prompt(Role, StepId, Attempt) ->
  iolist_to_binary([
    <<"You are an agent role='">>,
    Role,
    <<"' executing step_id='">>,
    StepId,
    <<"' attempt=">>,
    integer_to_binary(Attempt),
    <<". Follow the step prompt strictly and produce the required output format.">>
  ]).

tool_policy_for_step(StepRaw, State0) ->
  Defaults = openagentic_workflow_engine_utils:ensure_map(maps:get(defaults, State0, #{})),
  StepPolicy0 = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"tool_policy">>, tool_policy], #{})),
  DefaultPolicy0 = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(Defaults, [<<"tool_policy">>, tool_policy], #{})),
  Policy = maps:merge(DefaultPolicy0, StepPolicy0),

  Mode = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Policy, [<<"mode">>, mode], <<"default">>)),
  Allow0 = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(Policy, [<<"allow">>, allow], [])),
  Deny0 = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(Policy, [<<"deny">>, deny], [])),

  Allow = openagentic_workflow_engine_utils:uniq_bins([openagentic_workflow_engine_utils:to_bin(X) || X <- Allow0]),
  Deny = openagentic_workflow_engine_utils:uniq_bins([openagentic_workflow_engine_utils:to_bin(X) || X <- Deny0]),

  UserAnswerer = maps:get(user_answerer, maps:get(opts, State0, #{}), undefined),
  Gate =
    case Mode of
      <<"bypass">> -> openagentic_permissions:bypass();
      <<"deny">> -> openagentic_permissions:deny();
      <<"prompt">> -> openagentic_permissions:prompt(UserAnswerer);
      _ -> openagentic_permissions:default(UserAnswerer)
    end,

  AllowedTools =
    case {Allow, Deny} of
      {[], []} ->
        undefined;
      {A, _} when A =/= [] ->
        ensure_ask_user(A);
      {[], D} ->
        All = all_known_tool_names(),
        ensure_ask_user([T || T <- All, not lists:member(T, D)])
    end,
  {Gate, AllowedTools}.

ensure_ask_user(L0) ->
  L = openagentic_workflow_engine_utils:uniq_bins([openagentic_workflow_engine_utils:to_bin(X) || X <- openagentic_workflow_engine_utils:ensure_list_value(L0)]),
  case lists:member(<<"AskUserQuestion">>, L) of
    true -> L;
    false -> [<<"AskUserQuestion">> | L]
  end.

all_known_tool_names() ->
  [
    <<"AskUserQuestion">>,
    <<"List">>,
    <<"Read">>,
    <<"Glob">>,
    <<"Grep">>,
    <<"Write">>,
    <<"Edit">>,
    <<"Bash">>,
    <<"WebFetch">>,
    <<"WebSearch">>,
    <<"Skill">>,
    <<"SlashCommand">>,
    <<"NotebookEdit">>,
    <<"lsp">>,
    <<"TodoWrite">>,
    <<"Task">>,
    <<"Echo">>
  ].

%% ---- prompt & input binding ----
