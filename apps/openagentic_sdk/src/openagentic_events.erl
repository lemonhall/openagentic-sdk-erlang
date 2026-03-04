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

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(F) when is_float(F) -> iolist_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

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
