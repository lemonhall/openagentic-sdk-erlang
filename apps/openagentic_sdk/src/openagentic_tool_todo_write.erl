-module(openagentic_tool_todo_write).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"TodoWrite">>.

description() -> <<"Write or update a TODO list for the current session.">>.

run(Input0, _Ctx0) ->
  Input = ensure_map(Input0),
  Todos0 = maps:get(<<"todos">>, Input, maps:get(todos, Input, undefined)),
  case Todos0 of
    L when is_list(L), L =/= [] ->
      validate_todos(L);
    _ ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"TodoWrite: 'todos' must be a non-empty list">>}}
  end.

validate_todos(Todos) ->
  Statuses = [<<"pending">>, <<"in_progress">>, <<"completed">>, <<"cancelled">>],
  Priorities = [<<"low">>, <<"medium">>, <<"high">>],
  try
    {Pending, InProg, Completed, Cancelled} =
      lists:foldl(
        fun (T0, {P, IP, C, X}) ->
          case is_map(T0) of
            false ->
              throw({kotlin_error, <<"IllegalArgumentException">>, <<"TodoWrite: each todo must be an object">>});
            true ->
              T = T0,
              Content0 = maps:get(<<"content">>, T, maps:get(content, T, undefined)),
              Status0 = maps:get(<<"status">>, T, maps:get(status, T, undefined)),
              ActiveForm0 = maps:get(<<"activeForm">>, T, maps:get(activeForm, T, undefined)),
              Priority0 = maps:get(<<"priority">>, T, maps:get(priority, T, undefined)),
              Id0 = maps:get(<<"id">>, T, maps:get(id, T, undefined)),

              Content = string_trim_or_empty(Content0),
              Status = string_trim_or_empty(Status0),

              case byte_size(Content) > 0 of
                true -> ok;
                false -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"TodoWrite: todo 'content' must be a non-empty string">>})
              end,
              case lists:member(Status, Statuses) of
                true -> ok;
                false ->
                  throw(
                    {kotlin_error,
                      <<"IllegalArgumentException">>,
                      <<"TodoWrite: todo 'status' must be 'pending', 'in_progress', 'completed', or 'cancelled'">>}
                  )
              end,
              case ActiveForm0 of
                undefined -> ok;
                _ ->
                  AF = string_trim_or_empty(ActiveForm0),
                  case byte_size(AF) > 0 of
                    true -> ok;
                    false ->
                      throw(
                        {kotlin_error,
                          <<"IllegalArgumentException">>,
                          <<"TodoWrite: todo 'activeForm' must be a non-empty string when provided">>}
                      )
                  end
              end,
              case Priority0 of
                undefined -> ok;
                _ ->
                  Pr = string:trim(to_bin(Priority0)),
                  case lists:member(Pr, Priorities) of
                    true -> ok;
                    false ->
                      throw(
                        {kotlin_error,
                          <<"IllegalArgumentException">>,
                          <<"TodoWrite: todo 'priority' must be 'low', 'medium', or 'high' when provided">>}
                      )
                  end
              end,
              case Id0 of
                undefined -> ok;
                _ ->
                  Id = string_trim_or_empty(Id0),
                  case byte_size(Id) > 0 of
                    true -> ok;
                    false ->
                      throw(
                        {kotlin_error, <<"IllegalArgumentException">>, <<"TodoWrite: todo 'id' must be a non-empty string when provided">>}
                      )
                  end
              end,

              case Status of
            <<"pending">> -> {P + 1, IP, C, X};
            <<"in_progress">> -> {P, IP + 1, C, X};
            <<"completed">> -> {P, IP, C + 1, X};
            _ -> {P, IP, C, X + 1}
          end
          end
        end,
        {0, 0, 0, 0},
        Todos
      ),
    Total = length(Todos),
    {ok, #{
      message => <<"Updated todos">>,
      stats => #{
        total => Total,
        pending => Pending,
        in_progress => InProg,
        completed => Completed,
        cancelled => Cancelled
      }
    }}
  catch
    throw:Reason -> {error, Reason};
    C:R -> {error, {C, R}}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

string_trim_or_empty(undefined) -> <<>>;
string_trim_or_empty(B) when is_binary(B) -> string:trim(B);
string_trim_or_empty(L) when is_list(L) -> string_trim_or_empty(unicode:characters_to_binary(L, utf8));
string_trim_or_empty(_Other) -> <<>>.
