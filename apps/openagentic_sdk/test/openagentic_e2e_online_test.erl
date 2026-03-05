-module(openagentic_e2e_online_test).

-include_lib("eunit/include/eunit.hrl").

e2e_online_test_() ->
  case os:getenv("OPENAGENTIC_E2E") of
    false ->
      [];
    "" ->
      [];
    _ ->
      {timeout, 900, fun () -> run_e2e() end}
  end.

run_e2e() ->
  case openagentic_e2e_online:run() of
    ok -> ok;
    {warn, _AllowedWarnings} -> ok;
    {skip, _Why} -> ok;
    {error, Reason} -> erlang:error({e2e_failed, Reason})
  end.

