-module(openagentic_hitl_order_test).

-include_lib("eunit/include/eunit.hrl").

hitl_question_is_emitted_before_answerer_blocks_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  Answerer =
    fun (_Q) ->
      Sid = only_session_id(Root),
      Events = openagentic_session_store:read_events(Root, Sid),
      ?assert(has_type(Events, <<"user.question">>)),
      <<"yes">>
    end,
  Gate = openagentic_permissions:default(Answerer),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider_prompt,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => Gate,
    user_answerer => Answerer,
    tools => [],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  ?assertEqual(<<"OK">>, maps:get(final_text, Res)).

has_type(Events, TypeBin) ->
  lists:any(
    fun (E0) ->
      E = ensure_map(E0),
      maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =:= TypeBin
    end,
    Events
  ).

only_session_id(Root0) ->
  Root = ensure_list(Root0),
  SessionsDir = filename:join([Root, "sessions"]),
  case file:list_dir(SessionsDir) of
    {ok, [Sid]} -> Sid;
    {ok, L} -> erlang:error({expected_single_session, L});
    Err -> erlang:error({no_sessions_dir, Err})
  end.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_hitl_order_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
