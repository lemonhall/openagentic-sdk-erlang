-module(openagentic_events).

-export([
  system_init/3,
  user_message/1,
  user_compaction/2,
  user_question/3,
  hook_event/7,
  assistant_delta/1,
  tool_use/3,
  tool_result/5,
  tool_output_compacted/2,
  provider_event/1,
  assistant_message/1,
  assistant_message/2,
  %% workflow (local control plane)
  workflow_init/5,
  workflow_step_start/5,
  workflow_step_output/6,
  workflow_step_event/5,
  workflow_guard_fail/5,
  workflow_step_pass/4,
  workflow_transition/5,
  workflow_cancelled/4,
  workflow_done/5,
  result/7,
  %% legacy (kept for compatibility)
  result/2,
  runtime_error/5,
  %% legacy (kept for compatibility)
  runtime_error/2
]).

-define(SDK_VERSION, <<"0.0.0">>).

system_init(SessionId, Cwd, Extra) ->
  Base = #{
    type => <<"system.init">>,
    session_id => to_bin(SessionId),
    cwd => to_bin(Cwd),
    sdk_version => ?SDK_VERSION
  },
  case Extra of
    M when is_map(M) -> maps:merge(Base, M);
    _ -> Base
  end.

user_message(Text) ->
  #{type => <<"user.message">>, text => to_bin(Text)}.

user_compaction(Auto0, Reason0) ->
  Auto = bool_true(Auto0),
  Base = #{type => <<"user.compaction">>, auto => Auto},
  case Reason0 of
    undefined -> Base;
    null -> Base;
    <<>> -> Base;
    "" -> Base;
    R -> Base#{reason => to_bin(R)}
  end.

user_question(QuestionId, Prompt, Choices) ->
  #{
    type => <<"user.question">>,
    question_id => to_bin(QuestionId),
    prompt => to_bin(Prompt),
    choices => [to_bin(C) || C <- Choices]
  }.

hook_event(HookPoint, Name, Matched, DurationMs, Action, ErrorType, ErrorMessage) ->
  Base = #{
    type => <<"hook.event">>,
    hook_point => to_bin(HookPoint),
    name => to_bin(Name),
    matched => Matched
  },
  Base2 =
    case DurationMs of
      undefined -> Base;
      _ -> Base#{duration_ms => DurationMs}
    end,
  Base3 =
    case Action of
      undefined -> Base2;
      <<>> -> Base2;
      "" -> Base2;
      _ -> Base2#{action => to_bin(Action)}
    end,
  Base4 =
    case ErrorType of
      undefined -> Base3;
      <<>> -> Base3;
      "" -> Base3;
      _ -> Base3#{error_type => to_bin(ErrorType)}
    end,
  case ErrorMessage of
    undefined -> Base4;
    <<>> -> Base4;
    "" -> Base4;
    _ -> Base4#{error_message => to_bin(ErrorMessage)}
  end.

tool_use(ToolUseId, Name, Input) ->
  #{
    type => <<"tool.use">>,
    tool_use_id => to_bin(ToolUseId),
    name => to_bin(Name),
    input => ensure_map(Input)
  }.

tool_result(ToolUseId, Output, IsError, ErrorType, ErrorMessage) ->
  Base = #{
    type => <<"tool.result">>,
    tool_use_id => to_bin(ToolUseId),
    is_error => IsError
  },
  Base2 =
    case Output of
      undefined -> Base;
      null -> Base;
      _ -> Base#{output => Output}
    end,
  case IsError of
    true ->
      Base2#{
        error_type => to_bin(ErrorType),
        error_message => to_bin(ErrorMessage)
      };
    false ->
      Base2
  end.

tool_output_compacted(ToolUseId0, CompactedTs0) ->
  ToolUseId = to_bin(ToolUseId0),
  Ts =
    case CompactedTs0 of
      undefined -> undefined;
      null -> undefined;
      T when is_float(T) -> T;
      T when is_integer(T) -> T * 1.0;
      B when is_binary(B) ->
        case (catch binary_to_float(string:trim(B))) of
          F when is_float(F) -> F;
          _ -> undefined
        end;
      _ -> undefined
    end,
  Base = #{type => <<"tool.output_compacted">>, tool_use_id => ToolUseId},
  case Ts of
    undefined -> Base;
    _ -> Base#{compacted_ts => Ts}
  end.

assistant_delta(TextDelta0) ->
  #{type => <<"assistant.delta">>, text_delta => to_bin(TextDelta0)}.

assistant_message(Text) ->
  assistant_message(Text, false).

assistant_message(Text, IsSummary0) ->
  IsSummary = bool_true(IsSummary0),
  #{type => <<"assistant.message">>, text => to_bin(Text), is_summary => IsSummary}.

%% ---- workflow events ----

workflow_init(WorkflowId0, WorkflowName0, DslPath0, DslHash0, Extra0) ->
  Base = #{
    type => <<"workflow.init">>,
    workflow_id => to_bin(WorkflowId0),
    workflow_name => to_bin(WorkflowName0),
    dsl_path => to_bin(DslPath0),
    dsl_sha256 => to_bin(DslHash0)
  },
  Extra =
    case Extra0 of
      M when is_map(M) -> M;
      _ -> #{}
    end,
  maps:merge(Base, Extra).

workflow_step_start(WorkflowId0, StepId0, Role0, Attempt0, StepSessionId0) ->
  #{
    type => <<"workflow.step.start">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0),
    role => to_bin(Role0),
    attempt => to_int(Attempt0),
    step_session_id => to_bin(StepSessionId0)
  }.

workflow_step_output(WorkflowId0, StepId0, Attempt0, StepSessionId0, Output0, OutputFormat0) ->
  Base = #{
    type => <<"workflow.step.output">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0),
    attempt => to_int(Attempt0),
    step_session_id => to_bin(StepSessionId0),
    output => Output0
  },
  case OutputFormat0 of
    undefined -> Base;
    null -> Base;
    <<>> -> Base;
    "" -> Base;
    F -> Base#{output_format => to_bin(F)}
  end.

workflow_step_event(WorkflowId0, StepId0, StepSessionId0, StepEvent0, Extra0) ->
  StepEvent = ensure_map(StepEvent0),
  Extra1 =
    case Extra0 of
      M when is_map(M) -> M;
      _ -> #{}
    end,
  Extra = drop_undefined(Extra1),
  Base = #{
    type => <<"workflow.step.event">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0),
    step_session_id => to_bin(StepSessionId0),
    step_event => StepEvent
  },
  maps:merge(Base, Extra).

workflow_guard_fail(WorkflowId0, StepId0, Attempt0, GuardName0, Reasons0) ->
  Reasons =
    case Reasons0 of
      L when is_list(L) -> [to_bin(R) || R <- L];
      B when is_binary(B) -> [B];
      _ -> []
    end,
  Base = #{
    type => <<"workflow.guard.fail">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0),
    attempt => to_int(Attempt0)
  },
  Base2 =
    case GuardName0 of
      undefined -> Base;
      null -> Base;
      <<>> -> Base;
      "" -> Base;
      G -> Base#{guard => to_bin(G)}
    end,
  Base2#{reasons => Reasons}.

workflow_step_pass(WorkflowId0, StepId0, Attempt0, NextStepId0) ->
  Base = #{
    type => <<"workflow.step.pass">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0),
    attempt => to_int(Attempt0)
  },
  case NextStepId0 of
    null -> Base;
    undefined -> Base;
    <<>> -> Base;
    "" -> Base;
    Next -> Base#{next_step_id => to_bin(Next)}
  end.

workflow_transition(WorkflowId0, FromStepId0, Outcome0, ToStepId0, Reason0) ->
  Base = #{
    type => <<"workflow.transition">>,
    workflow_id => to_bin(WorkflowId0),
    from_step_id => to_bin(FromStepId0),
    outcome => to_bin(Outcome0)
  },
  Base2 =
    case ToStepId0 of
      null -> Base;
      undefined -> Base;
      <<>> -> Base;
      "" -> Base;
      To -> Base#{to_step_id => to_bin(To)}
    end,
  case Reason0 of
    undefined -> Base2;
    null -> Base2;
    <<>> -> Base2;
    "" -> Base2;
    R -> Base2#{reason => to_bin(R)}
  end.

workflow_cancelled(WorkflowId0, StepId0, Reason0, By0) ->
  Base = #{
    type => <<"workflow.cancelled">>,
    workflow_id => to_bin(WorkflowId0),
    step_id => to_bin(StepId0)
  },
  Base2 =
    case Reason0 of
      undefined -> Base;
      null -> Base;
      <<>> -> Base;
      "" -> Base;
      R -> Base#{reason => to_bin(R)}
    end,
  case By0 of
    undefined -> Base2;
    null -> Base2;
    <<>> -> Base2;
    "" -> Base2;
    B -> Base2#{by => to_bin(B)}
  end.

workflow_done(WorkflowId0, WorkflowName0, Status0, FinalText0, Extra0) ->
  Base = #{
    type => <<"workflow.done">>,
    workflow_id => to_bin(WorkflowId0),
    workflow_name => to_bin(WorkflowName0),
    status => to_bin(Status0),
    final_text => to_bin(FinalText0)
  },
  Extra =
    case Extra0 of
      M when is_map(M) -> M;
      _ -> #{}
    end,
  maps:merge(Base, Extra).

provider_event(JsonMap) when is_map(JsonMap) ->
  #{type => <<"provider.event">>, json => JsonMap}.

result(FinalText0, SessionId0, StopReason0, Usage0, ResponseId0, ProviderMetadata0, Steps0) ->
  Base =
    #{
      type => <<"result">>,
      final_text => to_bin(FinalText0),
      session_id => to_bin(SessionId0)
    },
  BaseStop =
    case StopReason0 of
      undefined -> Base;
      null -> Base;
      <<>> -> Base;
      "" -> Base;
      SR -> Base#{stop_reason => to_bin(SR)}
    end,
  Base2 =
    case Usage0 of
      undefined -> BaseStop;
      null -> BaseStop;
      U when is_map(U) -> BaseStop#{usage => U};
      _ -> BaseStop
    end,
  Base3 =
    case ResponseId0 of
      undefined -> Base2;
      null -> Base2;
      <<>> -> Base2;
      "" -> Base2;
      Rid -> Base2#{response_id => to_bin(Rid)}
    end,
  Base4 =
    case ProviderMetadata0 of
      undefined -> Base3;
      null -> Base3;
      M when is_map(M) -> Base3#{provider_metadata => M};
      _ -> Base3
    end,
  case Steps0 of
    undefined -> Base4;
    null -> Base4;
    S when is_integer(S) -> Base4#{steps => S};
    _ -> Base4
  end.

%% legacy: kept to avoid breaking older call sites; prefer result/7
result(ResponseId, StopReason) ->
  #{
    type => <<"result">>,
    response_id => to_bin(ResponseId),
    stop_reason => to_bin(StopReason)
  }.

runtime_error(Phase0, ErrorType0, ErrorMessage0, Provider0, ToolUseId0) ->
  Base = #{type => <<"runtime.error">>, phase => to_bin(Phase0), error_type => to_bin(ErrorType0)},
  Base2 =
    case ErrorMessage0 of
      undefined -> Base;
      null -> Base;
      <<>> -> Base;
      "" -> Base;
      M -> Base#{error_message => to_bin(M)}
    end,
  Base3 =
    case Provider0 of
      undefined -> Base2;
      null -> Base2;
      <<>> -> Base2;
      "" -> Base2;
      P -> Base2#{provider => to_bin(P)}
    end,
  case ToolUseId0 of
    undefined -> Base3;
    null -> Base3;
    <<>> -> Base3;
    "" -> Base3;
    T -> Base3#{tool_use_id => to_bin(T)}
  end.

%% legacy: kept to avoid breaking older call sites; prefer runtime_error/5
runtime_error(Message, Raw) ->
  #{
    type => <<"runtime.error">>,
    message => to_bin(Message),
    raw => Raw
  }.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

drop_undefined(M) when is_map(M) ->
  maps:from_list([{K, V} || {K, V} <- maps:to_list(M), V =/= undefined]);
drop_undefined(_) ->
  #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(F) when is_float(F) -> iolist_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

to_int(I) when is_integer(I) -> I;
to_int(B) when is_binary(B) ->
  case (catch binary_to_integer(string:trim(B))) of
    I when is_integer(I) -> I;
    _ -> 0
  end;
to_int(L) when is_list(L) ->
  case (catch list_to_integer(string:trim(L))) of
    I when is_integer(I) -> I;
    _ -> 0
  end;
to_int(_) -> 0.

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of
    <<"true">> -> true;
    <<"1">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    _ -> false
  end;
bool_true(L) when is_list(L) ->
  bool_true(unicode:characters_to_binary(L, utf8));
bool_true(I) when is_integer(I) -> I =/= 0;
bool_true(_) -> false.
