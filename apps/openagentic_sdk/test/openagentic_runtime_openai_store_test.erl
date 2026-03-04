-module(openagentic_runtime_openai_store_test).

-include_lib("eunit/include/eunit.hrl").

passes_store_true_when_unspecified_test() ->
  Root = test_root(),
  put(expected_store, true),
  {ok, _} =
    openagentic_runtime:query(
      <<"hi">>,
      #{
        session_root => Root,
        provider_mod => openagentic_testing_provider_store,
        protocol => responses,
        tools => [],
        api_key => <<"x">>,
        model => <<"m">>,
        event_sink => fun (_Ev) -> ok end
      }
    ),
  ok.

passes_store_true_when_enabled_test() ->
  Root = test_root(),
  put(expected_store, true),
  {ok, _} =
    openagentic_runtime:query(
      <<"hi">>,
      #{
        session_root => Root,
        provider_mod => openagentic_testing_provider_store,
        protocol => responses,
        openai_store => true,
        tools => [],
        api_key => <<"x">>,
        model => <<"m">>,
        event_sink => fun (_Ev) -> ok end
      }
    ),
  ok.

passes_store_false_when_disabled_test() ->
  Root = test_root(),
  put(expected_store, false),
  {ok, _} =
    openagentic_runtime:query(
      <<"hi">>,
      #{
        session_root => Root,
        provider_mod => openagentic_testing_provider_store,
        protocol => responses,
        openai_store => false,
        tools => [],
        api_key => <<"x">>,
        model => <<"m">>,
        event_sink => fun (_Ev) -> ok end
      }
    ),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_runtime_openai_store_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

