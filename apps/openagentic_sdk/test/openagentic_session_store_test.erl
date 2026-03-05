-module(openagentic_session_store_test).

-include_lib("eunit/include/eunit.hrl").

create_and_append_read_test() ->
  Root = test_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{project => <<"x">>}),
  {ok, E1} = openagentic_session_store:append_event(Root, Sid, #{type => <<"t1">>}),
  {ok, E2} = openagentic_session_store:append_event(Root, Sid, #{type => <<"t2">>}),
  ?assertEqual(1, maps:get(seq, E1)),
  ?assertEqual(2, maps:get(seq, E2)),
  Events = openagentic_session_store:read_events(Root, Sid),
  ?assert(length(Events) >= 2).

repair_truncated_tail_test() ->
  Root = test_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  Dir = openagentic_session_store:session_dir(Root, Sid),
  Path = filename:join([Dir, "events.jsonl"]),
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  %% Write a valid line without newline + a truncated line.
  ok =
    file:write_file(
      Path,
      <<
        "{\"type\":\"ok\",\"seq\":1,\"ts\":1.0}\n",
        "{\"type\":\"bad\""
      >>
    ),
  {ok, _E} = openagentic_session_store:append_event(Root, Sid, #{type => <<"after">>}),
  Events = openagentic_session_store:read_events(Root, Sid),
  %% Should parse at least the first valid line and the appended one.
  ?assert(length(Events) >= 2).

append_event_sanitizes_undefined_and_terms_test() ->
  Root = test_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  %% These values would previously crash jsone:encode/1 (undefined/pid/fun).
  Ev0 =
    #{
      type => <<"t">>,
      undef => undefined,
      pid => self(),
      'fun' => fun () -> ok end,
      tuple => {a, 1}
    },
  {ok, Stored} = openagentic_session_store:append_event(Root, Sid, Ev0),
  ?assertEqual(<<"t">>, maps:get(type, Stored)),
  ?assertNot(maps:is_key(undef, Stored)),
  ?assert(is_binary(maps:get(pid, Stored))),
  ?assert(is_binary(maps:get('fun', Stored))),
  ?assert(is_binary(maps:get(tuple, Stored))),
  Events = openagentic_session_store:read_events(Root, Sid),
  %% Decoded keys are binaries; ensure our "pid"/"fun"/"tuple" fields survived as strings.
  [Last | _] = lists:reverse(Events),
  ?assert(maps:is_key(<<"pid">>, Last)),
  ?assert(maps:is_key(<<"fun">>, Last)),
  ?assert(maps:is_key(<<"tuple">>, Last)),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_session_store_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
