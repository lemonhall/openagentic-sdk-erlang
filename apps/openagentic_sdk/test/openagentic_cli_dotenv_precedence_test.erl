-module(openagentic_cli_dotenv_precedence_test).

-include_lib("eunit/include/eunit.hrl").

dotenv_overrides_env_test() ->
  Tmp = test_root(),
  DotPath = filename:join([Tmp, ".env"]),
  ok =
    file:write_file(
      DotPath,
      <<
        "OPENAI_API_KEY=dotkey\n"
        "MODEL=dotmodel\n"
        "OPENAI_BASE_URL=\"https://dot.base\"\n"
        "OPENAI_API_KEY_HEADER=x-dot\n"
        "OPENAI_STORE=false\n"
      >>
    ),
  with_env(
    fun () ->
      {Flags, _} = openagentic_cli:parse_flags_for_test(["--project-dir", Tmp]),
      Opts = openagentic_cli:runtime_opts_for_test(Flags),
      ?assertEqual(<<"dotkey">>, maps:get(api_key, Opts)),
      ?assertEqual(<<"dotmodel">>, maps:get(model, Opts)),
      ?assertEqual(<<"https://dot.base">>, maps:get(base_url, Opts)),
      ?assertEqual(<<"x-dot">>, maps:get(api_key_header, Opts)),
      ?assertEqual(false, maps:get(openai_store, Opts)),
      ok
    end,
    #{
      "OPENAI_API_KEY" => "envkey",
      "OPENAI_MODEL" => "envmodel",
      "OPENAI_BASE_URL" => "https://env.base",
      "OPENAI_API_KEY_HEADER" => "x-env",
      "OPENAI_STORE" => "true"
    }
  ).

flags_override_dotenv_test() ->
  Tmp = test_root(),
  DotPath = filename:join([Tmp, ".env"]),
  ok = file:write_file(DotPath, <<"OPENAI_API_KEY=dotkey\nMODEL=dotmodel\n">>),
  with_env(
    fun () ->
      {Flags, _} = openagentic_cli:parse_flags_for_test(["--project-dir", Tmp, "--api-key", "flagkey", "--model", "flagmodel"]),
      Opts = openagentic_cli:runtime_opts_for_test(Flags),
      ?assertEqual(<<"flagkey">>, maps:get(api_key, Opts)),
      ?assertEqual(<<"flagmodel">>, maps:get(model, Opts)),
      ok
    end,
    #{
      "OPENAI_API_KEY" => "envkey",
      "OPENAI_MODEL" => "envmodel"
    }
  ).

dotenv_missing_optional_keys_do_not_become_false_test() ->
  Tmp = test_root(),
  DotPath = filename:join([Tmp, ".env"]),
  %% Only required keys; omit OPENAI_API_KEY_HEADER / OPENAI_BASE_URL.
  ok = file:write_file(DotPath, <<"OPENAI_API_KEY=dotkey\nMODEL=dotmodel\n">>),
  %% Ensure env vars are unset (os:getenv/1 -> false).
  with_unset_env(
    ["OPENAI_API_KEY_HEADER", "OPENAI_BASE_URL"],
    fun () ->
      {Flags, _} = openagentic_cli:parse_flags_for_test(["--project-dir", Tmp]),
      Opts = openagentic_cli:runtime_opts_for_test(Flags),
      ?assertEqual(<<"authorization">>, maps:get(api_key_header, Opts)),
      ?assertEqual(<<"https://api.openai.com/v1">>, maps:get(base_url, Opts)),
      ok
    end
  ).

with_unset_env(Keys, Fun) ->
  Old = [{K, os:getenv(K)} || K <- Keys],
  lists:foreach(fun (K) -> _ = os:unsetenv(K) end, Keys),
  try
    Fun()
  after
    lists:foreach(fun ({K, false}) -> _ = os:unsetenv(K); ({K, V}) -> _ = os:putenv(K, V) end, Old)
  end.

with_env(Fun, Vars) ->
  %% Snapshot old values and restore after.
  Names = maps:keys(Vars),
  Old = [{N, os:getenv(N)} || N <- Names],
  lists:foreach(fun ({N, V}) -> true = os:putenv(N, V) end, maps:to_list(Vars)),
  try
    Fun()
  after
    lists:foreach(fun ({N, false}) -> _ = os:unsetenv(N); ({N, V}) -> _ = os:putenv(N, V) end, Old)
  end.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_cli_dotenv_precedence_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
