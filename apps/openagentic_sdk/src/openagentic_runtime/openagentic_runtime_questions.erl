-module(openagentic_runtime_questions).
-export([handle_ask_user_question/5,normalize_questions/1,ask_all_questions_loop/6,parse_option_labels/1,first_non_empty/2]).

handle_ask_user_question(ToolUseId0, ToolName0, ToolInput0, HookCtx, State0) ->
  ToolUseId = openagentic_runtime_utils:to_bin(ToolUseId0),
  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
  ToolInput = openagentic_runtime_utils:ensure_map(ToolInput0),
  Questions = normalize_questions(ToolInput),
  case Questions of
    [] ->
      openagentic_runtime_events:append_event(
        State0,
        openagentic_events:tool_result(
          ToolUseId,
          undefined,
          true,
          <<"InvalidAskUserQuestionInput">>,
          <<"AskUserQuestion: 'questions' must be a non-empty list">>
        )
      );
    _ ->
      case maps:get(user_answerer, State0, undefined) of
        F when is_function(F, 1) ->
          {State1, Answers} = ask_all_questions_loop(Questions, ToolUseId, 0, F, State0, #{}),
          Output = #{questions => Questions, answers => Answers},
          openagentic_runtime_events:finish_tool_success(ToolUseId, ToolName, Output, HookCtx, State1);
        _ ->
          openagentic_runtime_events:append_event(
            State0,
            openagentic_events:tool_result(
              ToolUseId,
              undefined,
              true,
              <<"NoUserAnswerer">>,
              <<"AskUserQuestion: no userAnswerer is configured">>
            )
          )
      end
  end.

normalize_questions(Input) ->
  QuestionsEl = maps:get(<<"questions">>, Input, maps:get(questions, Input, undefined)),
  case QuestionsEl of
    M when is_map(M) -> [M];
    L when is_list(L) -> [openagentic_runtime_utils:ensure_map(X) || X <- L, is_map(X)];
    _ ->
      QText0 =
        first_non_empty(Input, [
          <<"question">>, question,
          <<"prompt">>, prompt
        ]),
      case QText0 of
        undefined ->
          [];
        _ ->
          QText = openagentic_runtime_utils:to_bin(QText0),
          OptsEl = maps:get(<<"options">>, Input, maps:get(options, Input, maps:get(<<"choices">>, Input, maps:get(choices, Input, undefined)))),
          Labels = parse_option_labels(OptsEl),
          Q = #{
            <<"question">> => QText,
            <<"options">> => [#{<<"label">> => Lbl} || Lbl <- Labels]
          },
          [Q]
      end
  end.

ask_all_questions_loop([], _ToolUseId, _I, _F, State0, Answers) ->
  {State0, Answers};
ask_all_questions_loop([Q0 | Rest], ToolUseId, I, F, State0, Answers0) ->
  Q = openagentic_runtime_utils:ensure_map(Q0),
  QText = string:trim(openagentic_runtime_utils:to_bin(maps:get(<<"question">>, Q, <<>>))),
  case byte_size(QText) > 0 of
    false ->
      ask_all_questions_loop(Rest, ToolUseId, I + 1, F, State0, Answers0);
    true ->
      Labels = parse_option_labels(maps:get(<<"options">>, Q, undefined)),
      Choices = case Labels of [] -> [<<"ok">>]; _ -> Labels end,
      Qid = iolist_to_binary([ToolUseId, <<":">>, integer_to_binary(I)]),
      Uq = openagentic_events:user_question(Qid, QText, Choices),
      State1 = openagentic_runtime_events:append_event(State0, Uq),
      Ans = F(Uq),
      Answers1 = Answers0#{QText => Ans},
      ask_all_questions_loop(Rest, ToolUseId, I + 1, F, State1, Answers1)
  end.

parse_option_labels(undefined) -> [];
parse_option_labels(L) when is_list(L) ->
  lists:filtermap(
    fun (El0) ->
      case El0 of
        M when is_map(M) ->
          Lbl0 = first_non_empty(M, [<<"label">>, label, <<"name">>, name, <<"value">>, value]),
          case Lbl0 of
            undefined -> false;
            V ->
              S = string:trim(openagentic_runtime_utils:to_bin(V)),
              case byte_size(S) > 0 of true -> {true, S}; false -> false end
          end;
        _ ->
          S = string:trim(openagentic_runtime_utils:to_bin(El0)),
          case byte_size(S) > 0 of true -> {true, S}; false -> false end
      end
    end,
    L
  );
parse_option_labels(M) when is_map(M) ->
  parse_option_labels(maps:get(<<"options">>, M, maps:get(<<"choices">>, M, undefined)));
parse_option_labels(_) ->
  [].

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = openagentic_runtime_utils:to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

%% ---- permission gate helpers (Kotlin parity) ----
