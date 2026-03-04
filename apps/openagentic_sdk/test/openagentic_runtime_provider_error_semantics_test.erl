-module(openagentic_runtime_provider_error_semantics_test).

-include_lib("eunit/include/eunit.hrl").

http_429_is_provider_rate_limit_exception_test() ->
  Root = test_root(),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider_http_429,
    provider_retry => #{max_retries => 0},
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    tools => [],
    max_steps => 1,
    base_url => <<"https://api.openai.com/v1">>
  },
  {error, {runtime_error, _Reason, Sid}} = openagentic_runtime:query(<<"hi">>, Opts),
  Events = openagentic_session_store:read_events(Root, Sid),
  Err = first_type(Events, <<"runtime.error">>),
  ?assertEqual(<<"provider">>, get_any(Err, phase, <<"phase">>, <<>>)),
  ?assertEqual(<<"ProviderRateLimitException">>, get_any(Err, error_type, <<"error_type">>, <<>>)),
  Msg = get_any(Err, error_message, <<"error_message">>, <<>>),
  ?assert(binary:match(Msg, <<"HTTP 429 from">>) =/= nomatch),
  ok.

stream_end_without_completed_is_provider_invalid_response_exception_test() ->
  Root = test_root(),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider_stream_fail,
    provider_retry => #{max_retries => 0},
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    tools => [],
    max_steps => 1
  },
  {error, {runtime_error, _Reason, Sid}} = openagentic_runtime:query(<<"hi">>, Opts),
  Events = openagentic_session_store:read_events(Root, Sid),
  Err = first_type(Events, <<"runtime.error">>),
  ?assertEqual(<<"provider">>, get_any(Err, phase, <<"phase">>, <<>>)),
  ?assertEqual(<<"ProviderInvalidResponseException">>, get_any(Err, error_type, <<"error_type">>, <<>>)),
  Msg = get_any(Err, error_message, <<"error_message">>, <<>>),
  ?assert(binary:match(Msg, <<"stream ended without response.completed">>) =/= nomatch),
  ok.

missing_required_is_session_illegal_argument_exception_test() ->
  Root = test_root(),
  Opts = #{
    session_root => Root,
    provider_mod => openagentic_testing_provider_missing_required,
    provider_retry => #{max_retries => 0},
    api_key => <<"dummy">>,
    model => <<"dummy">>,
    permission_gate => openagentic_permissions:bypass(),
    tools => [],
    max_steps => 1
  },
  {error, {runtime_error, _Reason, Sid}} = openagentic_runtime:query(<<"hi">>, Opts),
  Events = openagentic_session_store:read_events(Root, Sid),
  Err = first_type(Events, <<"runtime.error">>),
  ?assertEqual(<<"session">>, get_any(Err, phase, <<"phase">>, <<>>)),
  ?assertEqual(<<"IllegalArgumentException">>, get_any(Err, error_type, <<"error_type">>, <<>>)),
  Msg = get_any(Err, error_message, <<"error_message">>, <<>>),
  ?assert(binary:match(Msg, <<"apiKey is required">>) =/= nomatch),
  ok.

first_type(Events0, TypeBin) ->
  Events = ensure_list(Events0),
  case lists:dropwhile(
         fun (E0) ->
           E = ensure_map(E0),
           maps:get(<<"type">>, E, maps:get(type, E, <<>>)) =/= TypeBin
         end,
         Events
       ) of
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

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_runtime_provider_error_semantics_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].
