-module(openagentic_workflow_mgr_test).

-include_lib("eunit/include/eunit.hrl").

default_idle_timeout_is_five_minutes_test() ->
  ?assertEqual(300000, openagentic_workflow_mgr:idle_timeout_ms_for_test(#{})).

note_progress_treats_direct_and_wrapped_events_as_activity_test() ->
  Root = test_root(),
  Sid = tracked_session(Root),
  try
    ok = openagentic_workflow_mgr:note_progress(Sid, #{type => <<"tool.result">>, tool_name => <<"Read">>}),
    Item1 =
      wait_for_item(
        Sid,
        fun (Item) ->
          maps:get(last_event_type, Item, undefined) =:= <<"tool.result">>
            andalso is_integer(maps:get(last_progress_ms, Item, undefined))
        end
      ),
    ?assertEqual(<<"tool.result">>, maps:get(last_event_type, Item1)),
    ok =
      openagentic_workflow_mgr:note_progress(
        Sid,
        #{
          type => <<"workflow.step.event">>,
          step_id => <<"leaf_a">>,
          step_event => #{type => <<"tool.use">>, tool_name => <<"Read">>}
        }
      ),
    Item2 =
      wait_for_item(
        Sid,
        fun (Item) ->
          maps:get(last_event_type, Item, undefined) =:= <<"tool.use">>
            andalso is_integer(maps:get(last_progress_ms, Item, undefined))
        end
      ),
    ?assertEqual(<<"tool.use">>, maps:get(last_event_type, Item2))
  after
    reset_mgr()
  end.

fanout_forwarded_workflow_events_refresh_watchdog_progress_test() ->
  Root = test_root(),
  Sid = tracked_session(Root),
  try
    Parent = self(),
    Pending = #{make_ref() => #{step_id => <<"leaf_a">>, pid => self()}},
    State0 = #{session_root => Root, workflow_session_id => Sid},
    Ev =
      #{
        type => <<"workflow.step.event">>,
        step_id => <<"leaf_a">>,
        step_event => #{type => <<"assistant.delta">>, text_delta => <<"x">>}
      },
    _Sender =
      spawn(
        fun () ->
          timer:sleep(20),
          Parent ! {wf_event, Ev},
          timer:sleep(20),
          Parent !
            {fanout_result,
              <<"leaf_a">>,
              {ok,
                #{
                  attempt => 1,
                  output => <<"# Result\n\nok\n">>,
                  parsed => #{type => markdown},
                  output_format => <<"markdown">>,
                  step_session_id => <<"fanout_step_session">>
                }}}
        end
      ),
    {ok, _Results} = openagentic_workflow_engine:wait_for_fanout_for_test(Pending, #{}, State0),
    Item =
      wait_for_item(
        Sid,
        fun (Item0) ->
          maps:get(last_event_type, Item0, undefined) =:= <<"assistant.delta">>
            andalso is_integer(maps:get(last_progress_ms, Item0, undefined))
        end
      ),
    ?assertEqual(<<"assistant.delta">>, maps:get(last_event_type, Item))
  after
    reset_mgr()
  end.

tracked_session(Root) ->
  reset_mgr(),
  {ok, Sid0} = openagentic_session_store:create_session(Root, #{}),
  Sid = to_bin(Sid0),
  ok = openagentic_workflow_mgr:ensure_started(),
  Ref = make_ref(),
  _ =
    sys:replace_state(
      openagentic_workflow_mgr,
      fun (_State0) ->
        #{
          Sid =>
            #{
              pid => self(),
              mon_ref => Ref,
              queue => [],
              session_root => Root,
              engine_opts => #{},
              last_progress_ms => undefined,
              last_event_type => undefined
            }
        }
      end
    ),
  Sid.

wait_for_item(Sid, Pred) ->
  Deadline = erlang:monotonic_time(millisecond) + 1000,
  wait_for_item_loop(Sid, Pred, Deadline).

wait_for_item_loop(Sid, Pred, Deadline) ->
  State = sys:get_state(openagentic_workflow_mgr),
  case maps:find(Sid, State) of
    {ok, Item} ->
      case Pred(Item) of
        true ->
          Item;
        false ->
          maybe_wait_for_item(Sid, Pred, Deadline, State)
      end;
    error ->
      maybe_wait_for_item(Sid, Pred, Deadline, State)
  end.

maybe_wait_for_item(Sid, Pred, Deadline, State) ->
  case erlang:monotonic_time(millisecond) >= Deadline of
    true ->
      erlang:error({wait_for_item_timeout, Sid, State});
    false ->
      timer:sleep(10),
      wait_for_item_loop(Sid, Pred, Deadline)
  end.

reset_mgr() ->
  maybe_kill(whereis(openagentic_workflow_mgr)),
  timer:sleep(20),
  ok.

maybe_kill(Pid) when is_pid(Pid) ->
  unlink(Pid),
  exit(Pid, kill),
  receive
    {'EXIT', Pid, _} -> ok
  after 20 ->
    ok
  end;
maybe_kill(_) ->
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_workflow_mgr_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).