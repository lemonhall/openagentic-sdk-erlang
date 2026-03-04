-module(openagentic_tool_ask_user_question).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"AskUserQuestion">>.

description() -> <<"Ask the user a clarifying question.">>.

run(Input0, Ctx) ->
  Input = ensure_map(Input0),
  Questions = normalize_questions(Input),
  case Questions of
    [] ->
      {error, {invalid_input, <<"AskUserQuestion: 'questions' must be a non-empty list">>}};
    _ ->
      case maps:get(user_answerer, Ctx, undefined) of
        F when is_function(F, 1) ->
          ToolUseId = to_bin(maps:get(tool_use_id, Ctx, random_hex(8))),
          {Answers, _Idx} = ask_all(Questions, ToolUseId, 0, F, #{}),
          {ok, #{
            questions => Questions,
            answers => Answers
          }};
        _ ->
          {error, {no_user_answerer, <<"AskUserQuestion: no userAnswerer is configured">>}}
      end
  end.

normalize_questions(Input) ->
  QuestionsEl = maps:get(<<"questions">>, Input, maps:get(questions, Input, undefined)),
  case QuestionsEl of
    M when is_map(M) -> [M];
    L when is_list(L) -> [ensure_map(X) || X <- L, is_map(X)];
    _ ->
      QText0 =
        first_non_empty(Input, [
          <<"question">>, question,
          <<"prompt">>, prompt
        ]),
      case QText0 of
        undefined -> [];
        _ ->
          QText = to_bin(QText0),
          OptsEl = maps:get(<<"options">>, Input, maps:get(options, Input, maps:get(<<"choices">>, Input, maps:get(choices, Input, undefined)))),
          Labels = parse_option_labels(OptsEl),
          Q = #{
            <<"question">> => QText,
            <<"options">> => [#{<<"label">> => Lbl} || Lbl <- Labels]
          },
          [Q]
      end
  end.

ask_all([], _ToolUseId, I, _F, Answers) -> {Answers, I};
ask_all([Q0 | Rest], ToolUseId, I, F, Answers0) ->
  Q = ensure_map(Q0),
  QText = string:trim(to_bin(maps:get(<<"question">>, Q, <<>>))),
  Answers =
    case byte_size(QText) > 0 of
      false -> Answers0;
      true ->
        Labels = parse_option_labels(maps:get(<<"options">>, Q, undefined)),
        Choices = case Labels of [] -> [<<"ok">>]; _ -> Labels end,
        Qid = iolist_to_binary([ToolUseId, <<":">>, integer_to_binary(I)]),
        Uq = #{
          type => <<"user.question">>,
          question_id => Qid,
          prompt => QText,
          choices => Choices
        },
        Ans = F(Uq),
        Answers0#{QText => Ans}
    end,
  ask_all(Rest, ToolUseId, I + 1, F, Answers).

parse_option_labels(undefined) -> [];
parse_option_labels(L) when is_list(L) ->
  lists:filtermap(
    fun (El0) ->
      case El0 of
        M when is_map(M) ->
          Lbl0 = first_non_empty(M, [<<"label">>, label, <<"name">>, name, <<"value">>, value]),
          case Lbl0 of
            undefined -> false;
            V -> {true, string:trim(to_bin(V))}
          end;
        _ ->
          S = string:trim(to_bin(El0)),
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
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
