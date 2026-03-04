-module(openagentic_testing_provider_deltas).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  OnDelta = maps:get(on_delta, Req, maps:get(onDelta, Req, undefined)),
  _ = maybe_delta(OnDelta, <<"he">>),
  _ = maybe_delta(OnDelta, <<"llo">>),
  {ok, #{
    assistant_text => <<"hello">>,
    tool_calls => [],
    response_id => <<"resp_delta_1">>,
    usage => #{<<"total_tokens">> => 1}
  }}.

maybe_delta(F, Delta) when is_function(F, 1) ->
  try
    F(Delta)
  catch
    _:_ -> ok
  end;
maybe_delta(_, _Delta) ->
  ok.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

