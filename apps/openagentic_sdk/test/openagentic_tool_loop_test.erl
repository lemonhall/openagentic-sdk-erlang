-module(openagentic_tool_loop_test).

-include_lib("eunit/include/eunit.hrl").

tool_loop_runs_tool_and_persists_events_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  ?assert(has_type(Events, <<"tool.use">>)),
  ?assert(has_type(Events, <<"tool.result">>)),
  ?assert(has_type(Events, <<"assistant.message">>)),
  ?assertEqual(<<"OK">>, maps:get(final_text, Res)).

tool_loop_pre_hook_can_block_tool_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  HookEngine = #{
    pre_tool_use => [
      #{
        name => <<"block_echo">>,
        tool_name_pattern => <<"Echo">>,
        block => true,
        block_reason => <<"nope">>
      }
    ]
  },
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    hook_engine => HookEngine,
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  ?assert(has_type(Events, <<"hook.event">>)),
  ?assert(has_error_type(Events, <<"HookBlocked">>)),
  ?assertEqual(<<"OK">>, maps:get(final_text, Res)).

tool_loop_externalizes_large_tool_output_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  %% Force output artifacts on small threshold.
  Art = #{enabled => true, dir_name => "tool-output", max_bytes => 200, preview_max_chars => 200},
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider_big,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    tool_output_artifacts => Art,
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  Out = first_tool_output(Events),
  ?assertEqual(true, maps:get(<<"_openagentic_truncated">>, Out)),
  Path = maps:get(<<"artifact_path">>, Out, undefined),
  ?assert(Path =/= undefined),
  ?assert(filelib:is_file(binary_to_list(Path))),
  ?assertEqual(<<"OK">>, maps:get(final_text, Res)).

has_type(Events, TypeBin) ->
  lists:any(
    fun (E0) ->
      E = ensure_map(E0),
      maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =:= TypeBin
    end,
    Events
  ).

has_error_type(Events, TypeBin) ->
  lists:any(
    fun (E0) ->
      E = ensure_map(E0),
      case maps:get(<<"type">>, E, maps:get(type, E, <<>>)) of
        <<"tool.result">> ->
          maps:get(<<"error_type">>, E, maps:get(error_type, E, <<>>)) =:= TypeBin;
        _ ->
          false
      end
    end,
    Events
  ).

first_tool_output(Events) ->
  case lists:filter(
    fun (E0) ->
      E = ensure_map(E0),
      maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =:= <<"tool.result">> andalso
        maps:is_key(<<"output">>, E)
    end,
    Events
  ) of
    [E | _] -> ensure_map(maps:get(<<"output">>, ensure_map(E)));
    _ -> #{}
  end.

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.
