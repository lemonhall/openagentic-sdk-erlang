-module(openagentic_workflow_engine).

-export([run/4]).

-define(DEFAULT_MAX_STEPS, 50).

%% Synchronous, local-first workflow runner.
%%
%% - Loads + validates workflow DSL (JSON)
%% - Creates a workflow session for workflow.* events
%% - Runs steps sequentially (each step gets its own session)
%% - Enforces output contracts + deterministic guards
%%
%% Future: wrap in OTP (manager + gen_statem) for async start/status/cancel.

run(ProjectDir0, WorkflowRelPath0, ControllerInput0, Opts0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  WorkflowRelPath = ensure_list_str(WorkflowRelPath0),
  ControllerInput = to_bin(ControllerInput0),
  Opts = ensure_map(Opts0),
  SessionRoot = ensure_list_str(maps:get(session_root, Opts, openagentic_paths:default_session_root())),

  case openagentic_workflow_dsl:load_and_validate(ProjectDir, WorkflowRelPath, Opts) of
    {ok, Wf} ->
      case read_workflow_source(ProjectDir, WorkflowRelPath) of
        {ok, SrcBin} ->
          DslHash = sha256_hex(SrcBin),
          WfName = maps:get(<<"name">>, Wf, <<>>),
          WorkflowId = new_id(),
          {ok, WfSessionId0} =
            openagentic_session_store:create_session(SessionRoot, #{
              workflow_id => WorkflowId,
              workflow_name => WfName,
              dsl_path => to_bin(WorkflowRelPath),
              dsl_sha256 => DslHash
            }),
          WfSessionId = to_bin(WfSessionId0),
          ok = append_wf_event(SessionRoot, WfSessionId0, openagentic_events:system_init(WfSessionId, ProjectDir, #{})),
          ok =
            append_wf_event(
              SessionRoot,
              WfSessionId0,
              openagentic_events:workflow_init(WorkflowId, WfName, WorkflowRelPath, DslHash, #{project_dir => to_bin(ProjectDir)})
            ),
          State0 =
            #{
              project_dir => ProjectDir,
              session_root => SessionRoot,
              workflow_id => WorkflowId,
              workflow_name => WfName,
              workflow_session_id => WfSessionId0,
              workflow_rel_path => to_bin(WorkflowRelPath),
              defaults => ensure_map(maps:get(<<"defaults">>, Wf, #{})),
              steps_by_id => ensure_map(maps:get(<<"steps_by_id">>, Wf, #{})),
              controller_input => ControllerInput,
              step_outputs => #{},
              step_attempts => #{},
              opts => Opts
            },
          Start = maps:get(<<"start_step_id">>, Wf, <<>>),
          run_loop(to_bin(Start), State0);
        {error, Reason} ->
          {error, Reason}
      end;
    Err ->
      Err
  end.

%% ---- main loop ----

run_loop(StepId0, State0) ->
  StepId = to_bin(StepId0),
  case StepId of
    <<>> ->
      finalize(State0, <<"failed">>, <<"missing start step">>);
    _ ->
      StepsById = maps:get(steps_by_id, State0),
      case maps:find(StepId, StepsById) of
        error ->
          finalize(State0, <<"failed">>, iolist_to_binary([<<"unknown step: ">>, StepId]));
        {ok, StepRaw0} ->
          StepRaw = ensure_map(StepRaw0),
          Attempt0 = maps:get(StepId, maps:get(step_attempts, State0, #{}), 0),
          Attempt = Attempt0 + 1,
          MaxAttempts = step_max_attempts(StepRaw, State0),
          case Attempt =< MaxAttempts of
            false ->
              Msg = iolist_to_binary([<<"max_attempts exceeded for step ">>, StepId]),
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"max_attempts">>, [Msg])),
              finalize(State0, <<"failed">>, Msg);
            true ->
              State1 = put_in(State0, [step_attempts, StepId], Attempt),
              run_one_step(StepId, StepRaw, Attempt, State1)
          end
      end
  end.

run_one_step(StepId, StepRaw, Attempt, State0) ->
  Role = to_bin(get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepSessionId0 = create_step_session(State0, StepId, Role, Attempt),
  StepSessionId = to_bin(StepSessionId0),

  ok = append_wf_event(State0, openagentic_events:workflow_step_start(wf_id(State0), StepId, Role, Attempt, StepSessionId)),

  case resolve_prompt(State0, StepRaw) of
    {ok, PromptText} ->
      InputText = bind_input(State0, StepRaw),
      UserPrompt = build_user_prompt(PromptText, InputText),
      ExecRes = run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw),
      case ExecRes of
        {ok, StepOut0} ->
          StepOut = to_bin(StepOut0),
          OutFormat = infer_output_format(StepRaw),
          ok =
            append_wf_event(
              State0,
              openagentic_events:workflow_step_output(wf_id(State0), StepId, Attempt, StepSessionId, StepOut, OutFormat)
            ),
          case eval_step_output(StepRaw, StepOut) of
            {ok, Parsed} ->
              State1 = put_in(State0, [step_outputs, StepId], #{output => StepOut, parsed => Parsed, step_session_id => StepSessionId}),
              Next = step_ref(StepRaw, [<<"on_pass">>, on_pass]),
              ok = append_wf_event(State1, openagentic_events:workflow_step_pass(wf_id(State1), StepId, Attempt, Next)),
              ok = append_wf_event(State1, openagentic_events:workflow_transition(wf_id(State1), StepId, <<"pass">>, Next, <<>>)),
              case Next of
                null -> finalize(State1, <<"completed">>, StepOut);
                _ -> run_loop(Next, State1)
              end;
            {error, Reasons} ->
              ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"guards">>, Reasons)),
              NextFail = step_ref(StepRaw, [<<"on_fail">>, on_fail]),
              ok = append_wf_event(State0, openagentic_events:workflow_transition(wf_id(State0), StepId, <<"fail">>, NextFail, <<"guard_failed">>)),
              case NextFail of
                null -> finalize(State0, <<"failed">>, join_bins(Reasons, <<"\n">>));
                _ -> run_loop(NextFail, State0)
              end
          end;
        {error, Reason} ->
          ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"executor">>, [to_bin(Reason)])),
          finalize(State0, <<"failed">>, to_bin(Reason))
      end;
    {error, Reason} ->
      ok = append_wf_event(State0, openagentic_events:workflow_guard_fail(wf_id(State0), StepId, Attempt, <<"prompt">>, [to_bin(Reason)])),
      finalize(State0, <<"failed">>, to_bin(Reason))
  end.

%% ---- executor ----

run_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts = maps:get(opts, State0, #{}),
  Ctx =
    #{
      project_dir => to_bin(maps:get(project_dir, State0)),
      session_root => to_bin(maps:get(session_root, State0)),
      workflow_id => wf_id(State0),
      workflow_session_id => to_bin(maps:get(workflow_session_id, State0)),
      step_id => StepId,
      role => Role,
      attempt => Attempt,
      step_session_id => to_bin(StepSessionId0),
      user_prompt => UserPrompt
    },
  case maps:get(step_executor, Opts, undefined) of
    F1 when is_function(F1, 1) ->
      F1(Ctx);
    F2 when is_function(F2, 2) ->
      F2(Ctx, StepRaw);
    _ ->
      default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw)
  end.

default_step_executor(State0, StepId, Role, Attempt, StepSessionId0, UserPrompt, StepRaw) ->
  Opts0 = maps:get(opts, State0, #{}),
  MaxSteps = step_max_steps(StepRaw, State0, maps:get(max_steps, Opts0, ?DEFAULT_MAX_STEPS)),
  {Gate, AllowedTools} = tool_policy_for_step(StepRaw, State0),
  RuntimeOpts =
    Opts0#{
      project_dir => maps:get(project_dir, State0),
      cwd => maps:get(project_dir, State0),
      session_root => maps:get(session_root, State0),
      resume_session_id => StepSessionId0,
      system_prompt => role_system_prompt(Role, StepId, Attempt),
      max_steps => MaxSteps,
      permission_gate => Gate,
      allowed_tools => AllowedTools
    },
  case openagentic_runtime:query(UserPrompt, RuntimeOpts) of
    {ok, #{final_text := Txt}} -> {ok, Txt};
    {ok, _Other} -> {ok, <<>>};
    {error, Reason} -> {error, Reason}
  end.

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
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  StepPolicy0 = ensure_map(get_any(StepRaw, [<<"tool_policy">>, tool_policy], #{})),
  DefaultPolicy0 = ensure_map(get_any(Defaults, [<<"tool_policy">>, tool_policy], #{})),
  Policy = maps:merge(DefaultPolicy0, StepPolicy0),

  Mode = to_bin(get_any(Policy, [<<"mode">>, mode], <<"default">>)),
  Allow0 = ensure_list_value(get_any(Policy, [<<"allow">>, allow], [])),
  Deny0 = ensure_list_value(get_any(Policy, [<<"deny">>, deny], [])),

  Allow = uniq_bins([to_bin(X) || X <- Allow0]),
  Deny = uniq_bins([to_bin(X) || X <- Deny0]),

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
  L = uniq_bins([to_bin(X) || X <- ensure_list_value(L0)]),
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

resolve_prompt(State0, StepRaw) ->
  Prompt0 = ensure_map(get_any(StepRaw, [<<"prompt">>, prompt], #{})),
  T = to_bin(get_any(Prompt0, [<<"type">>, type], <<>>)),
  ProjectDir = maps:get(project_dir, State0),
  case T of
    <<"inline">> ->
      Txt = to_bin(get_any(Prompt0, [<<"text">>, text], <<>>)),
      case byte_size(string:trim(Txt)) > 0 of
        true -> {ok, Txt};
        false -> {error, <<"prompt.text is required">>}
      end;
    <<"file">> ->
      Rel = to_bin(get_any(Prompt0, [<<"path">>, path], <<>>)),
      case openagentic_fs:resolve_project_path(ProjectDir, Rel) of
        {ok, Abs} ->
          case file:read_file(Abs) of
            {ok, Bin} -> {ok, Bin};
            _ -> {error, <<"prompt file read failed">>}
          end;
        _ ->
          {error, <<"prompt path unsafe">>}
      end;
    _ ->
      {error, <<"unknown prompt type">>}
  end.

bind_input(State0, StepRaw) ->
  Input0 = ensure_map(get_any(StepRaw, [<<"input">>, input], #{})),
  T = to_bin(get_any(Input0, [<<"type">>, type], <<>>)),
  StepOutputs = maps:get(step_outputs, State0, #{}),
  case T of
    <<"controller_input">> ->
      maps:get(controller_input, State0, <<>>);
    <<"step_output">> ->
      From = to_bin(get_any(Input0, [<<"step_id">>, step_id], <<>>)),
      case maps:get(From, StepOutputs, undefined) of
        #{output := Out} -> to_bin(Out);
        _ -> <<>>
      end;
    <<"merge">> ->
      Sources = ensure_list_value(get_any(Input0, [<<"sources">>, sources], [])),
      merge_sources(Sources, StepOutputs, 0, []);
    _ ->
      <<>>
  end.

merge_sources([], _StepOutputs, _Idx, AccRev) ->
  iolist_to_binary(lists:reverse(AccRev));
merge_sources([Src0 | Rest], StepOutputs, Idx, AccRev) ->
  Src = ensure_map(Src0),
  T = to_bin(get_any(Src, [<<"type">>, type], <<>>)),
  Chunk =
    case T of
      <<"step_output">> ->
        Sid = to_bin(get_any(Src, [<<"step_id">>, step_id], <<>>)),
        case maps:get(Sid, StepOutputs, undefined) of
          #{output := Out} -> to_bin(Out);
          _ -> <<>>
        end;
      <<"controller_input">> ->
        <<>>;
      _ ->
        <<>>
    end,
  Header = iolist_to_binary([<<"\n\n--- source ">>, integer_to_binary(Idx + 1), <<" (">>, T, <<") ---\n\n">>]),
  merge_sources(Rest, StepOutputs, Idx + 1, [Chunk, Header | AccRev]).

build_user_prompt(PromptText, InputText) ->
  iolist_to_binary([PromptText, <<"\n\n---\n\n# 输入\n\n">>, InputText, <<"\n">>]).

infer_output_format(StepRaw) ->
  OutC = ensure_map(get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  T = to_bin(get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"decision">> -> <<"json">>;
    <<"json_object">> -> <<"json">>;
    _ -> <<"markdown">>
  end.

%% ---- evaluation ----

eval_step_output(StepRaw, Output0) ->
  Output = to_bin(Output0),
  OutC = ensure_map(get_any(StepRaw, [<<"output_contract">>, output_contract], #{})),
  case eval_output_contract(OutC, Output) of
    {ok, Parsed} ->
      Guards = ensure_list_value(get_any(StepRaw, [<<"guards">>, guards], [])),
      case eval_guards(Guards, Output, Parsed) of
        ok -> {ok, Parsed};
        {error, Reasons} -> {error, Reasons}
      end;
    {error, Reasons} ->
      {error, Reasons}
  end.

eval_output_contract(OutC, Output) ->
  T = to_bin(get_any(OutC, [<<"type">>, type], <<>>)),
  case T of
    <<"markdown_sections">> ->
      Req = ensure_list_value(get_any(OutC, [<<"required">>, required], [])),
      case missing_sections(Req, Output) of
        [] -> {ok, #{type => markdown}};
        Missing ->
          {error, [iolist_to_binary([<<"missing sections: ">>, join_bins([to_bin(M) || M <- Missing], <<", ">>)])]}
      end;
    <<"decision">> ->
      case parse_json_object(Output) of
        {ok, Obj} ->
          Allowed = [to_bin(X) || X <- ensure_list_value(get_any(OutC, [<<"allowed">>, allowed], []))],
          Decision = to_bin(get_any(Obj, [<<"decision">>, decision], <<>>)),
          case lists:member(Decision, Allowed) of
            true -> {ok, Obj#{type => decision}};
            false -> {error, [<<"invalid decision">>]}
          end;
        {error, _} ->
          {error, [<<"decision output must be a JSON object">>]}
      end;
    <<"json_object">> ->
      case parse_json_object(Output) of
        {ok, Obj} -> {ok, Obj#{type => json_object}};
        {error, _} -> {error, [<<"output must be a JSON object">>]}
      end;
    _ ->
      {ok, #{type => unknown}}
  end.

eval_guards([], _Output, _Parsed) ->
  ok;
eval_guards([G0 | Rest], Output, Parsed) ->
  G = ensure_map(G0),
  T = to_bin(get_any(G, [<<"type">>, type], <<>>)),
  Res =
    case T of
      <<"max_words">> ->
        Limit = int_or_default(get_any(G, [<<"value">>, value], undefined), 0),
        Count = word_count(Output),
        case (Limit > 0 andalso Count > Limit) of
          true -> {error, [iolist_to_binary([<<"max_words exceeded: ">>, integer_to_binary(Count), <<">">>, integer_to_binary(Limit)])]};
          false -> ok
        end;
      <<"regex_must_match">> ->
        Pat = to_bin(get_any(G, [<<"pattern">>, pattern], <<>>)),
        case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
          match -> ok;
          _ -> {error, [<<"regex_must_match failed">>]}
        end;
      <<"markdown_sections">> ->
        Req = ensure_list_value(get_any(G, [<<"required">>, required], [])),
        case missing_sections(Req, Output) of
          [] -> ok;
          Missing -> {error, [iolist_to_binary([<<"missing sections: ">>, join_bins([to_bin(M) || M <- Missing], <<", ">>)])]}
        end;
      <<"decision_requires_reasons">> ->
        When = to_bin(get_any(G, [<<"when">>, 'when'], <<>>)),
        Decision = to_bin(get_any(Parsed, [<<"decision">>, decision], <<>>)),
        case Decision =:= When of
          false -> ok;
          true ->
            ReasonsList = ensure_list_value(get_any(Parsed, [<<"reasons">>, reasons], [])),
            ChangesList = ensure_list_value(get_any(Parsed, [<<"required_changes">>, required_changes], [])),
            case (ReasonsList =/= []) andalso (ChangesList =/= []) of
              true -> ok;
              false -> {error, [<<"decision_requires_reasons failed">>]}
            end
        end;
      <<"requires_evidence">> ->
        %% v1 runner: advisory (enforced in async control plane later).
        ok;
      _ ->
        ok
    end,
  case Res of
    ok -> eval_guards(Rest, Output, Parsed);
    {error, Reasons} -> {error, Reasons}
  end.

missing_sections(Req0, Output0) ->
  Output = to_bin(Output0),
  Req = [to_bin(X) || X <- ensure_list_value(Req0)],
  [R || R <- Req, not has_section(R, Output)].

has_section(Title0, Output0) ->
  Title = string:trim(to_bin(Title0)),
  Output = to_bin(Output0),
  case byte_size(Title) of
    0 -> true;
    _ ->
      Pat = iolist_to_binary([<<"(?m)^\\s*#+\\s+">>, re_escape(Title), <<"\\s*$">>]),
      case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
        match -> true;
        _ -> false
      end
  end.

re_escape(Bin0) ->
  Bin = to_bin(Bin0),
  lists:foldl(
    fun ({From, To}, Acc) -> binary:replace(Acc, From, To, [global]) end,
    Bin,
    [
      {<<"\\">>, <<"\\\\">>},
      {<<".">>, <<"\\.">>},
      {<<"+">>, <<"\\+">>},
      {<<"*">>, <<"\\*">>},
      {<<"?">>, <<"\\?">>},
      {<<"^">>, <<"\\^">>},
      {<<"$">>, <<"\\$">>},
      {<<"(">>, <<"\\(">>},
      {<<")">>, <<"\\)">>},
      {<<"[">>, <<"\\[">>},
      {<<"]">>, <<"\\]">>},
      {<<"{">>, <<"\\{">>},
      {<<"}">>, <<"\\}">>},
      {<<"|">>, <<"\\|">>}
    ]
  ).

word_count(Text0) ->
  Text = to_bin(Text0),
  Parts = re:split(Text, <<"\\s+">>, [unicode, {return, list}]),
  length([P || P <- Parts, string:trim(P) =/= ""]).

parse_json_object(Output0) ->
  Output = string:trim(to_bin(Output0)),
  Bin = strip_code_fences(Output),
  try
    Obj = openagentic_json:decode(Bin),
    case is_map(Obj) of
      true -> {ok, Obj};
      false -> {error, not_object}
    end
  catch
    _:_ -> {error, invalid_json}
  end.

strip_code_fences(Bin0) ->
  Bin = to_bin(Bin0),
  case re:run(Bin, <<"(?s)^```[a-zA-Z0-9_-]*\\s*(\\{.*\\})\\s*```\\s*$">>, [{capture, [1], binary}, unicode]) of
    {match, [Inner]} -> Inner;
    _ -> Bin
  end.

%% ---- sessions & workflow events ----

create_step_session(State0, StepId, Role, Attempt) ->
  Root = maps:get(session_root, State0),
  Meta =
    #{
      workflow_id => wf_id(State0),
      step_id => StepId,
      role => Role,
      attempt => Attempt
    },
  {ok, Sid} = openagentic_session_store:create_session(Root, Meta),
  SidBin = to_bin(Sid),
  ok = append_wf_event(Root, Sid, openagentic_events:system_init(SidBin, maps:get(project_dir, State0), #{})),
  Sid.

append_wf_event(State0, Ev) ->
  append_wf_event(maps:get(session_root, State0), maps:get(workflow_session_id, State0), Ev).

append_wf_event(Root0, Sid0, Ev) ->
  Root = ensure_list_str(Root0),
  Sid = ensure_list_str(Sid0),
  {ok, _Stored} = openagentic_session_store:append_event(Root, Sid, Ev),
  ok.

finalize(State0, Status0, FinalText0) ->
  Status = to_bin(Status0),
  FinalText = to_bin(FinalText0),
  ok =
    append_wf_event(
      State0,
      openagentic_events:workflow_done(wf_id(State0), maps:get(workflow_name, State0, <<>>), Status, FinalText, #{})
    ),
  {ok, #{
    workflow_id => wf_id(State0),
    workflow_name => maps:get(workflow_name, State0, <<>>),
    workflow_session_id => to_bin(maps:get(workflow_session_id, State0)),
    status => Status,
    final_text => FinalText
  }}.

wf_id(State0) ->
  maps:get(workflow_id, State0, <<>>).

%% ---- step defaults ----

step_max_attempts(StepRaw, State0) ->
  StepMax = get_any(StepRaw, [<<"max_attempts">>, max_attempts], undefined),
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  DefMax = get_any(Defaults, [<<"max_attempts">>, max_attempts], 1),
  int_or_default(StepMax, int_or_default(DefMax, 1)).

step_max_steps(StepRaw, State0, Fallback) ->
  StepMax = get_any(StepRaw, [<<"max_steps">>, max_steps], undefined),
  Defaults = ensure_map(maps:get(defaults, State0, #{})),
  DefMax = get_any(Defaults, [<<"max_steps">>, max_steps], undefined),
  int_or_default(StepMax, int_or_default(DefMax, int_or_default(Fallback, ?DEFAULT_MAX_STEPS))).

%% ---- file/hash helpers ----

read_workflow_source(ProjectDir0, RelPath0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  RelPath = ensure_list_str(RelPath0),
  case openagentic_fs:resolve_project_path(ProjectDir, RelPath) of
    {ok, Abs} -> file:read_file(Abs);
    {error, unsafe_path} -> {error, unsafe_path}
  end.

sha256_hex(Bin) when is_binary(Bin) ->
  Hash = crypto:hash(sha256, Bin),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Hash]).

new_id() ->
  Bytes = crypto:strong_rand_bytes(16),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

%% ---- generic helpers ----

step_ref(StepRaw, Keys) ->
  V = get_any(StepRaw, Keys, undefined),
  case V of
    null -> null;
    undefined -> null;
    B when is_binary(B) -> string:trim(B);
    L when is_list(L) -> string:trim(iolist_to_binary(L));
    A when is_atom(A) ->
      case A of
        null -> null;
        _ -> atom_to_binary(A, utf8)
      end;
    _ -> null
  end.

put_in(Map0, [K1, K2], V) ->
  M1 = ensure_map(maps:get(K1, Map0, #{})),
  Map0#{K1 := M1#{K2 => V}}.

uniq_bins(L0) ->
  uniq_bins([to_bin(X) || X <- ensure_list_value(L0)], #{}).

uniq_bins([], _Seen) -> [];
uniq_bins([B | Rest], Seen0) ->
  case maps:get(B, Seen0, false) of
    true -> uniq_bins(Rest, Seen0);
    false -> [B | uniq_bins(Rest, Seen0#{B => true})]
  end.

join_bins([], _Sep) -> <<>>;
join_bins([B], _Sep) -> to_bin(B);
join_bins([B | Rest], Sep) -> iolist_to_binary([to_bin(B), Sep, join_bins(Rest, Sep)]).

get_any(Map, Keys, Default) ->
  get_any_loop(ensure_map(Map), Keys, Default).

get_any_loop(_Map, [], Default) -> Default;
get_any_loop(Map, [K | Rest], Default) ->
  case maps:find(K, Map) of
    {ok, V} -> V;
    error -> get_any_loop(Map, Rest, Default)
  end.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_str(B) when is_binary(B) -> binary_to_list(B);
ensure_list_str(L) when is_list(L) -> L;
ensure_list_str(A) when is_atom(A) -> atom_to_list(A);
ensure_list_str(undefined) -> [];
ensure_list_str(null) -> [];
ensure_list_str(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(_) -> [].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
