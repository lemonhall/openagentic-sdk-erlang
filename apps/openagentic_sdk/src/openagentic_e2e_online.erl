-module(openagentic_e2e_online).
-export([suite/0, run/0]).

run() ->
  openagentic_e2e_online_runner:run().

suite() ->
  Res = run(),
  case Res of
    ok ->
      io:format("E2E suite OK.~n", []),
      ok;
    {warn, Ws} ->
      io:format("E2E suite OK with allowed warnings: ~p~n", [Ws]),
      ok;
    {skip, _} ->
      io:format("E2E disabled. Set OPENAGENTIC_E2E=1 to run online tests.~n", []),
      erlang:halt(2);
    {error, Err} ->
      io:format("E2E suite FAILED: ~p~n", [Err]),
      erlang:halt(1)
  end.
