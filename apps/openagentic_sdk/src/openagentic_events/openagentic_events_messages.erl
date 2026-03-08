-module(openagentic_events_messages).
-export([assistant_delta/1, assistant_message/1, assistant_message/2, system_init/3, user_compaction/2, user_message/1, user_question/3]).

-define(SDK_VERSION, <<"0.0.0">>).

system_init(SessionId, Cwd, Extra) ->
  Base = #{type => <<"system.init">>, session_id => openagentic_events_utils:to_bin(SessionId), cwd => openagentic_events_utils:to_bin(Cwd), sdk_version => ?SDK_VERSION},
  case Extra of M when is_map(M) -> maps:merge(Base, M); _ -> Base end.

user_message(Text) -> #{type => <<"user.message">>, text => openagentic_events_utils:to_bin(Text)}.

user_compaction(Auto0, Reason0) ->
  Base = #{type => <<"user.compaction">>, auto => openagentic_events_utils:bool_true(Auto0)},
  case Reason0 of undefined -> Base; null -> Base; <<>> -> Base; "" -> Base; R -> Base#{reason => openagentic_events_utils:to_bin(R)} end.

user_question(QuestionId, Prompt, Choices) -> #{type => <<"user.question">>, question_id => openagentic_events_utils:to_bin(QuestionId), prompt => openagentic_events_utils:to_bin(Prompt), choices => [openagentic_events_utils:to_bin(C) || C <- Choices]}.

assistant_delta(TextDelta0) -> #{type => <<"assistant.delta">>, text_delta => openagentic_events_utils:to_bin(TextDelta0)}.
assistant_message(Text) -> assistant_message(Text, false).
assistant_message(Text, IsSummary0) -> #{type => <<"assistant.message">>, text => openagentic_events_utils:to_bin(Text), is_summary => openagentic_events_utils:bool_true(IsSummary0)}.
