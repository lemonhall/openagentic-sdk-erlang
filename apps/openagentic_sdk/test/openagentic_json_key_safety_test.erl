-module(openagentic_json_key_safety_test).

-include_lib("eunit/include/eunit.hrl").

unknown_case_store_json_key_stays_binary_test() ->
  Key = <<"zz_case_store_unknown_key_20260309">>,
  ?assertMatch({'EXIT', _}, (catch binary_to_existing_atom(Key, utf8))),
  Json = <<"{\"zz_case_store_unknown_key_20260309\":1}\n">>,
  Decoded = openagentic_case_store_repo_persist:decode_json(Json),
  ?assertEqual(1, maps:get(Key, Decoded)),
  ?assertMatch({'EXIT', _}, (catch binary_to_existing_atom(Key, utf8))),
  ok.

unknown_scheduler_store_json_key_stays_binary_test() ->
  Root = test_root(),
  Path = filename:join([Root, "scheduler.json"]),
  Key = <<"zz_scheduler_unknown_key_20260309">>,
  ?assertMatch({'EXIT', _}, (catch binary_to_existing_atom(Key, utf8))),
  ok = file:write_file(Path, <<"{\"zz_scheduler_unknown_key_20260309\":2}\n">>),
  Decoded = openagentic_case_scheduler_store:read_json(Path),
  ?assertEqual(2, maps:get(Key, Decoded)),
  ?assertMatch({'EXIT', _}, (catch binary_to_existing_atom(Key, utf8))),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_json_key_safety_test", integer_to_list(erlang:unique_integer([positive, monotonic]))]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.
