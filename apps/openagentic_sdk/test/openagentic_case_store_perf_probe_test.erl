-module(openagentic_case_store_perf_probe_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [tmp_root/0]).


perf_probe_can_measure_due_scheduler_runs_test() ->
  Root = tmp_root(),
  Result =
    openagentic_case_store_perf_probe:run_baseline(
      #{
        output_root => Root,
        case_count => 1,
        tasks_per_case => 2,
        active_tasks_per_case => 2,
        scheduled_tasks_per_case => 1,
        mail_per_case => 1,
        unread_per_case => 1,
        runtime_opts => #{provider_mod => openagentic_testing_provider_monitoring_success}
      }
    ),
  Observed = maps:get(observed, Result, #{}),
  ?assertEqual(1, maps:get(scheduler_triggered_run_count, Observed, 0)),
  ?assertEqual(0, maps:get(scheduler_skipped_count, Observed, 0)),
  ok.

perf_probe_test_() ->
  {timeout, 300, fun perf_probe_body/0}.

perf_probe_body() ->
  case os:getenv("OPENAGENTIC_PERF_PROBE") of
    false -> ok;
    "1" ->
      Result = openagentic_case_store_perf_probe:run_baseline(build_opts()),
      Json = openagentic_json:encode_safe(Result),
      maybe_write_json(Json),
      io:format("PERF_JSON=~s~n", [Json]),
      ok;
    _ -> ok
  end.

build_opts() ->
  maps:from_list(
    [
      {output_root, getenv_bin("OPENAGENTIC_PERF_OUTPUT_ROOT")},
      {case_count, getenv_int("OPENAGENTIC_PERF_CASE_COUNT")},
      {tasks_per_case, getenv_int("OPENAGENTIC_PERF_TASKS_PER_CASE")},
      {active_tasks_per_case, getenv_int("OPENAGENTIC_PERF_ACTIVE_TASKS_PER_CASE")},
      {scheduled_tasks_per_case, getenv_nonneg_int("OPENAGENTIC_PERF_SCHEDULED_TASKS_PER_CASE")},
      {mail_per_case, getenv_int("OPENAGENTIC_PERF_MAIL_PER_CASE")},
      {unread_per_case, getenv_int("OPENAGENTIC_PERF_UNREAD_PER_CASE")},
      {runtime_opts, build_runtime_opts()}
    ]
  ).

build_runtime_opts() ->
  maps:from_list(
    [
      {provider_mod, getenv_bin("OPENAGENTIC_PERF_PROVIDER_MOD")}
    ]
  ).

maybe_write_json(Json) ->
  case os:getenv("OPENAGENTIC_PERF_JSON_OUT") of
    false -> ok;
    "" -> ok;
    Path -> file:write_file(Path, <<Json/binary, "\n">>)
  end.

getenv_bin(Name) ->
  case os:getenv(Name) of
    false -> undefined;
    "" -> undefined;
    Value -> unicode:characters_to_binary(Value, utf8)
  end.

getenv_int(Name) ->
  case os:getenv(Name) of
    false -> undefined;
    "" -> undefined;
    Value ->
      case catch list_to_integer(string:trim(Value)) of
        I when is_integer(I), I > 0 -> I;
        _ -> undefined
      end
  end.

getenv_nonneg_int(Name) ->
  case os:getenv(Name) of
    false -> undefined;
    "" -> undefined;
    Value ->
      case catch list_to_integer(string:trim(Value)) of
        I when is_integer(I), I >= 0 -> I;
        _ -> undefined
      end
  end.
