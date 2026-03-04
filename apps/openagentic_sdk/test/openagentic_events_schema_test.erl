-module(openagentic_events_schema_test).

-include_lib("eunit/include/eunit.hrl").

events_schema_persisted_meta_test() ->
  Root = test_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),

  {ok, Ev1} = openagentic_session_store:append_event(Root, Sid, openagentic_events:system_init(Sid, ".", #{})),
  {ok, Ev2} = openagentic_session_store:append_event(Root, Sid, openagentic_events:user_message(<<"hi">>)),
  {ok, Ev3} = openagentic_session_store:append_event(Root, Sid, openagentic_events:tool_use(<<"tid">>, <<"Read">>, #{})),
  {ok, Ev4} = openagentic_session_store:append_event(Root, Sid, openagentic_events:tool_result(<<"tid">>, #{<<"ok">> => true}, false, <<>>, <<>>)),
  {ok, Ev5} = openagentic_session_store:append_event(Root, Sid, openagentic_events:assistant_message(<<"done">>, false)),
  {ok, Ev6} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:result(<<"done">>, Sid, <<"end">>, #{<<"total_tokens">> => 1}, <<"resp_1">>, undefined, 3)
    ),
  {ok, Ev7} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:runtime_error(<<"provider">>, <<"ProviderError">>, <<"oops">>, <<"prov">>, <<"tid">>)
    ),

  lists:foreach(fun assert_has_meta/1, [Ev1, Ev2, Ev3, Ev4, Ev5, Ev6, Ev7]),

  ?assertEqual(<<"result">>, maps:get(type, Ev6)),
  ?assert(maps:is_key(final_text, Ev6)),
  ?assert(maps:is_key(session_id, Ev6)),
  ?assert(maps:is_key(stop_reason, Ev6)),
  ?assert(maps:is_key(usage, Ev6)),
  ?assert(maps:is_key(response_id, Ev6)),
  ?assert(maps:is_key(steps, Ev6)),

  %% tool.result success should not carry error fields.
  ?assertNot(maps:is_key(error_type, Ev4)),
  ?assertNot(maps:is_key(error_message, Ev4)),
  ok.

events_schema_optional_fields_omitted_test() ->
  %% Result: stop_reason omitted when undefined/null/blank.
  R0 = openagentic_events:result(<<"">>, <<"sid">>, undefined, undefined, undefined, undefined, undefined),
  ?assertNot(maps:is_key(stop_reason, R0)),
  ?assertNot(maps:is_key(usage, R0)),
  ?assertNot(maps:is_key(response_id, R0)),

  %% tool.result: output omitted when null.
  T0 = openagentic_events:tool_result(<<"tid">>, null, false, <<>>, <<>>),
  ?assertNot(maps:is_key(output, T0)),
  ok.

assert_has_meta(E) ->
  ?assert(maps:is_key(seq, E)),
  ?assert(is_integer(maps:get(seq, E))),
  ?assert(maps:is_key(ts, E)),
  ?assert(is_float(maps:get(ts, E))),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  filename:join([Cwd, ".tmp", "eunit", "openagentic_events_schema_test"]).

