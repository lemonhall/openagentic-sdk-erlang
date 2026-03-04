-module(openagentic_e2e).

-export([online_smoke/0]).

%% Online smoke test entrypoint.
%% Intentionally avoids printing secrets; relies on CLI/runtime error handling.
online_smoke() ->
  %% Minimal request; should not require tools.
  openagentic_cli:main(["run", "--no-stream", "ping"]),
  ok.

