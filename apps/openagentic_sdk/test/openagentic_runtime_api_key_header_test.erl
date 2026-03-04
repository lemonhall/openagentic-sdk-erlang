-module(openagentic_runtime_api_key_header_test).

-include_lib("eunit/include/eunit.hrl").

passes_api_key_header_to_provider_test() ->
  Root = test_root(),
  put(expected_api_key_header, <<"x-test-header">>),
  {ok, _} =
    openagentic_runtime:query(
      <<"hi">>,
      #{
        session_root => Root,
        provider_mod => openagentic_testing_provider_api_key_header,
        protocol => responses,
        api_key_header => <<"x-test-header">>,
        tools => [],
        api_key => <<"x">>,
        model => <<"m">>,
        event_sink => fun (_Ev) -> ok end
      }
    ),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_runtime_api_key_header_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

