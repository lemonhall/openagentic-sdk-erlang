-module(openagentic_tool_loop_test).

-include_lib("eunit/include/eunit.hrl").

tool_loop_runs_tool_and_persists_events_test() ->
  Root = test_root(),
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

has_type(Events, TypeBin) ->
  lists:any(
    fun (E0) ->
      E = ensure_map(E0),
      maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =:= TypeBin
    end,
    Events
  ).

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

