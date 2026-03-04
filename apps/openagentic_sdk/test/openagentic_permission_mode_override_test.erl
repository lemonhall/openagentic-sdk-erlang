-module(openagentic_permission_mode_override_test).

-include_lib("eunit/include/eunit.hrl").

session_permission_mode_overrides_gate_mode_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:default(undefined),
    session_permission_mode => deny,
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  ToolRes = first_tool_result(Events, <<"call_1">>),
  Msg = get_any(ToolRes, error_message, <<"error_message">>, <<>>),
  ?assert(binary:match(Msg, <<"PermissionGate(mode=DENY)">>) =/= nomatch),
  ok.

permission_mode_override_takes_precedence_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:default(undefined),
    session_permission_mode => deny,
    permission_mode_override => bypass,
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  ToolRes = first_tool_result(Events, <<"call_1">>),
  ?assertNot(has_any_key(ToolRes, error_type, <<"error_type">>)),
  ok.

no_override_defaults_to_prompt_without_user_answerer_test() ->
  Root = test_root(),
  _ = erlang:erase(openagentic_test_step),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider,
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:default(undefined),
    tools => [openagentic_tool_echo],
    max_steps => 5
  },
  {ok, Res} = openagentic_runtime:query(<<"hi">>, Opts),
  Sid = maps:get(session_id, Res),
  Events = openagentic_session_store:read_events(Root, Sid),
  ToolRes = first_tool_result(Events, <<"call_1">>),
  Msg = get_any(ToolRes, error_message, <<"error_message">>, <<>>),
  case binary:match(Msg, <<"mode=DEFAULT">>) of
    nomatch -> erlang:error({unexpected_deny_message, Msg, ToolRes});
    _ -> ok
  end,
  ok.

first_tool_result(Events0, ToolUseId) ->
  Events = ensure_list(Events0),
  Pred =
    fun (E0) ->
      E = ensure_map(E0),
      maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =:= <<"tool.result">> andalso
        maps:get(<<"tool_use_id">>, E, maps:get(tool_use_id, E, <<>>)) =:= ToolUseId
    end,
  case lists:dropwhile(fun (E) -> not Pred(E) end, Events) of
    [E | _] -> ensure_map(E);
    _ -> #{}
  end.

get_any(Map0, AtomKey, BinKey, Default) ->
  Map = ensure_map(Map0),
  case maps:get(AtomKey, Map, undefined) of
    undefined ->
      maps:get(BinKey, Map, Default);
    V ->
      V
  end.

has_any_key(Map0, AtomKey, BinKey) ->
  Map = ensure_map(Map0),
  maps:is_key(AtomKey, Map) orelse maps:is_key(BinKey, Map).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_permission_mode_override_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].
