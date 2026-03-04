-module(openagentic_testing_provider_prev).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Step = case erlang:get(openagentic_test_step_prev) of undefined -> 0; V -> V end,
  case Step of
    0 ->
      erlang:put(openagentic_test_step_prev, 1),
      Prev = maps:get(previous_response_id, Req, undefined),
      case Prev of
        <<"resp_2">> -> ok;
        _ -> erlang:error({expected_previous_response_id, <<"resp_2">>, Prev, Req})
      end,
      {ok, #{
        assistant_text => <<"OK">>,
        tool_calls => [],
        response_id => <<"resp_3">>,
        usage => #{}
      }};
    _ ->
      {ok, #{assistant_text => <<"OK">>, tool_calls => [], response_id => <<"resp_4">>, usage => #{}}}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

