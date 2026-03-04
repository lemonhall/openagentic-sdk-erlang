-module(openagentic_events).

-export([
  system_init/3,
  user_message/1,
  user_question/3,
  tool_use/3,
  tool_result/5,
  provider_event/1,
  assistant_message/1,
  result/2,
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

user_question(QuestionId, Prompt, Choices) ->
  #{
    type => <<"user.question">>,
    question_id => to_bin(QuestionId),
    prompt => to_bin(Prompt),
    choices => [to_bin(C) || C <- Choices]
  }.

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

assistant_message(Text) ->
  #{type => <<"assistant.message">>, text => to_bin(Text)}.

provider_event(JsonMap) when is_map(JsonMap) ->
  #{type => <<"provider.event">>, json => JsonMap}.

result(ResponseId, StopReason) ->
  #{
    type => <<"result">>,
    response_id => to_bin(ResponseId),
    stop_reason => to_bin(StopReason)
  }.

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
