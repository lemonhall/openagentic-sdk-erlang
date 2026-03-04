-module(openagentic_testing_provider).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Step = case erlang:get(openagentic_test_step) of undefined -> 0; V -> V end,
  case Step of
    0 ->
      erlang:put(openagentic_test_step, 1),
      {ok, #{
        assistant_text => <<>>,
        tool_calls => [
          #{tool_use_id => <<"call_1">>, name => <<"Echo">>, arguments => #{<<"text">> => <<"Hello">>}}
        ],
        response_id => <<"resp_1">>,
        usage => #{}
      }};
    1 ->
      erlang:put(openagentic_test_step, 2),
      Input = maps:get(input, Req, []),
      ok = assert_has_call_and_output(Input, <<"call_1">>),
      {ok, #{
        assistant_text => <<"OK">>,
        tool_calls => [],
        response_id => <<"resp_2">>,
        usage => #{}
      }};
    _ ->
      {ok, #{assistant_text => <<"OK">>, tool_calls => [], response_id => <<"resp_3">>, usage => #{}}}
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

