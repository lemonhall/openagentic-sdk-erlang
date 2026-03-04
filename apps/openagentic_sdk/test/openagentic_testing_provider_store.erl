-module(openagentic_testing_provider_store).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Expected = get(expected_store),
  Store = maps:get(store, Req, undefined),
  case Expected of
    undefined ->
      ok;
    _ when Store =:= Expected ->
      ok;
    _ ->
      erlang:error({expected_store_flag, Expected, Store, Req})
  end,
  {ok, #{assistant_text => <<>>, tool_calls => [], response_id => <<"resp_store_1">>, usage => #{}}}.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

