-module(openagentic_paths).

-export([default_agents_root/0, default_session_root/0]).

default_agents_root() ->
  case os:getenv("OPENAGENTIC_AGENTS_HOME") of
    false ->
      Home = case os:getenv("USERPROFILE") of false -> "."; V -> V end,
      filename:join([Home, ".agents"]);
    "" ->
      default_agents_root();
    V ->
      V
  end.

default_session_root() ->
  case os:getenv("OPENAGENTIC_SDK_HOME") of
    false ->
      %% Fallback for non-Windows environments; on your Windows setup we expect
      %% OPENAGENTIC_SDK_HOME to be set to an E: path.
      Home = case os:getenv("USERPROFILE") of false -> "."; V -> V end,
      filename:join([Home, ".openagentic-sdk"]);
    "" ->
      default_session_root();
    V ->
      V
  end.
