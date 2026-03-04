-module(openagentic_cli_flags_test).

-include_lib("eunit/include/eunit.hrl").

stream_defaults_on_test() ->
  with_cli_env(
    fun () ->
      Opts = openagentic_cli:runtime_opts_for_test(#{}),
      ?assertEqual(true, maps:get(include_partial_messages, Opts)),
      ok
    end
  ).

no_stream_flag_disables_streaming_test() ->
  with_cli_env(
    fun () ->
      {Flags, _Pos} = openagentic_cli:parse_flags_for_test(["--no-stream"]),
      Opts = openagentic_cli:runtime_opts_for_test(Flags),
      ?assertEqual(false, maps:get(include_partial_messages, Opts)),
      ok
    end
  ).

max_steps_clamps_to_kotlin_range_test() ->
  with_cli_env(
    fun () ->
      {Flags1, _} = openagentic_cli:parse_flags_for_test(["--max-steps", "0"]),
      Opts1 = openagentic_cli:runtime_opts_for_test(Flags1),
      ?assertEqual(1, maps:get(max_steps, Opts1)),

      {Flags2, _} = openagentic_cli:parse_flags_for_test(["--max-steps", "999"]),
      Opts2 = openagentic_cli:runtime_opts_for_test(Flags2),
      ?assertEqual(200, maps:get(max_steps, Opts2)),

      {Flags3, _} = openagentic_cli:parse_flags_for_test(["--max-steps", "42"]),
      Opts3 = openagentic_cli:runtime_opts_for_test(Flags3),
      ?assertEqual(42, maps:get(max_steps, Opts3)),
      ok
    end
  ).

compaction_flags_flow_into_runtime_opts_test() ->
  with_cli_env(
    fun () ->
      {Flags, _Pos} =
        openagentic_cli:parse_flags_for_test(
          ["--context-limit", "123", "--reserved", "10", "--input-limit", "77"]
        ),
      Opts = openagentic_cli:runtime_opts_for_test(Flags),
      Compaction = maps:get(compaction, Opts),
      ?assertEqual(123, maps:get(context_limit, Compaction)),
      ?assertEqual(10, maps:get(reserved, Compaction)),
      ?assertEqual(77, maps:get(input_limit, Compaction)),
      ok
    end
  ).

with_cli_env(Fun) ->
  OldKey = os:getenv("OPENAI_API_KEY"),
  OldModel = os:getenv("OPENAI_MODEL"),
  os:putenv("OPENAI_API_KEY", "test"),
  os:putenv("OPENAI_MODEL", "gpt-test"),
  try
    Fun()
  after
    restore_env("OPENAI_API_KEY", OldKey),
    restore_env("OPENAI_MODEL", OldModel)
  end.

restore_env(Name, false) ->
  _ = os:unsetenv(Name),
  ok;
restore_env(Name, Value) ->
  true = os:putenv(Name, Value),
  ok.

