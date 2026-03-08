-module(openagentic_tools_contract_test_support).
-export([restore_env/2, test_root/0]).

restore_env(Key, false) ->
  _ = os:unsetenv(Key),
  ok;
restore_env(Key, "") ->
  _ = os:putenv(Key, ""),
  ok;
restore_env(Key, V) ->
  _ = os:putenv(Key, V),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_tools_contract_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
