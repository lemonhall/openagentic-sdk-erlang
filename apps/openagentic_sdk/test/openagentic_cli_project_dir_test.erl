-module(openagentic_cli_project_dir_test).

-include_lib("eunit/include/eunit.hrl").

resolve_project_dir_walks_up_to_env_test() ->
  Root = test_root(),
  ok = file:write_file(filename:join([Root, ".env"]), <<"OPENAI_API_KEY=x\nMODEL=y\n">>),
  Nested = filename:join([Root, "_build", "default", "lib", "openagentic_sdk"]),
  ok = filelib:ensure_dir(filename:join([Nested, "x"])),
  ?assertEqual(Root, openagentic_cli:resolve_project_dir_for_test(Nested)).

resolve_project_dir_walks_up_to_rebar_config_test() ->
  Root = test_root(),
  ok = file:write_file(filename:join([Root, "rebar.config"]), <<"{erl_opts,[debug_info]}.\n">>),
  Nested = filename:join([Root, "apps", "openagentic_sdk", "ebin"]),
  ok = filelib:ensure_dir(filename:join([Nested, "x"])),
  ?assertEqual(Root, openagentic_cli:resolve_project_dir_for_test(Nested)).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_cli_project_dir_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

