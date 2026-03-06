-module(openagentic_testing_provider_task).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Input = ensure_list(maps:get(input, Req, [])),
  case has_system_marker(Input, openagentic_built_in_subagents:research_marker()) of
    true ->
      {ok, #{assistant_text => <<"Evidence gathered">>, tool_calls => [], response_id => <<"resp_sub_1">>, usage => #{}}};
    false ->
      Step = case erlang:get(openagentic_test_task_step) of undefined -> 0; V -> V end,
      case Step of
        0 ->
          erlang:put(openagentic_test_task_step, 1),
          {ok, #{
            assistant_text => <<>>,
            tool_calls => [
              #{
                tool_use_id => <<"call_task_1">>,
                name => <<"Task">>,
                arguments => #{agent => <<"research">>, prompt => <<"Collect 1-3 public facts for this claim.">>}
              }
            ],
            response_id => <<"resp_task_1">>,
            usage => #{}
          }};
        1 ->
          erlang:put(openagentic_test_task_step, 2),
          ok = assert_has_call_and_output(Input, <<"call_task_1">>),
          {ok, #{assistant_text => <<"OK">>, tool_calls => [], response_id => <<"resp_task_2">>, usage => #{}}};
        _ ->
          {ok, #{assistant_text => <<"OK">>, tool_calls => [], response_id => <<"resp_task_3">>, usage => #{}}}
      end
  end.

has_system_marker([], _Marker) -> false;
has_system_marker([Item0 | Rest], Marker) ->
  Item = ensure_map(Item0),
  Role = to_bin(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Content = to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
  case {Role, binary:match(Content, Marker)} of
    {<<"system">>, nomatch} -> has_system_marker(Rest, Marker);
    {<<"system">>, _} -> true;
    _ -> has_system_marker(Rest, Marker)
  end.

assert_has_call_and_output(InputItems0, CallId) ->
  InputItems = ensure_list(InputItems0),
  HasCall =
    lists:any(
      fun (I0) ->
        I = ensure_map(I0),
        maps:get(type, I, maps:get(<<"type">>, I, <<>>)) =:= <<"function_call">> andalso
          maps:get(call_id, I, maps:get(<<"call_id">>, I, <<>>)) =:= CallId
      end,
      InputItems
    ),
  HasOut =
    lists:any(
      fun (I0) ->
        I = ensure_map(I0),
        maps:get(type, I, maps:get(<<"type">>, I, <<>>)) =:= <<"function_call_output">> andalso
          maps:get(call_id, I, maps:get(<<"call_id">>, I, <<>>)) =:= CallId
      end,
      InputItems
    ),
  case {HasCall, HasOut} of
    {true, true} -> ok;
    _ -> erlang:error({missing_expected_items, HasCall, HasOut, InputItems})
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
