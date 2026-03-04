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

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

