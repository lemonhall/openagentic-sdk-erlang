-module(openagentic_partial_messages_test).

-include_lib("eunit/include/eunit.hrl").

include_partial_messages_emits_delta_but_does_not_persist_test() ->
  Root = test_root(),
  put(events, []),
  Sink =
    fun (Ev) ->
      L = case get(events) of undefined -> []; V -> V end,
      put(events, L ++ [Ev]),
      ok
    end,

  {ok, Out} =
    openagentic_runtime:query(
      <<"hi">>,
      #{
        session_root => Root,
        provider_mod => openagentic_testing_provider_deltas,
        tools => [],
        api_key => <<"x">>,
        model => <<"x">>,
        include_partial_messages => true,
        event_sink => Sink
      }
    ),
  Sid0 = maps:get(session_id, Out),
  Sid = to_bin(Sid0),
  ?assert(byte_size(Sid) > 0),

  %% Sink should have seen assistant.delta events.
  Seen = get(events),
  Deltas =
    [maps:get(text_delta, E, maps:get(<<"text_delta">>, E, <<>>)) || E <- Seen, maps:get(type, E, maps:get(<<"type">>, E, <<>>)) =:= <<"assistant.delta">>],
  ?assertEqual([<<"he">>, <<"llo">>], Deltas),

  %% But session store should not persist assistant.delta.
  Persisted = openagentic_session_store:read_events(Root, Sid),
  HasDelta =
    lists:any(
      fun (E0) ->
        E = ensure_map(E0),
        to_bin(maps:get(<<"type">>, E, maps:get(type, E, <<>>))) =:= <<"assistant.delta">>
      end,
      Persisted
    ),
  ?assertEqual(false, HasDelta),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_partial_messages_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

