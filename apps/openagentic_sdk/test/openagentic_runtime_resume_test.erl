-module(openagentic_runtime_resume_test).

-include_lib("eunit/include/eunit.hrl").

resume_session_passes_previous_response_id_test() ->
  Root = test_root(),
  %% First run: create session and produce a result with response_id resp_2.
  {ok, Out1} =
    openagentic_runtime:query(
      <<"hello">>,
      #{
        session_root => Root,
        session_metadata => #{},
        provider_mod => openagentic_testing_provider,
        tools => [openagentic_tool_echo],
        api_key => <<"x">>,
        model => <<"x">>
      }
    ),
  Sid0 = maps:get(session_id, Out1),
  Sid = to_bin(Sid0),
  ?assert(is_binary(Sid)),
  ?assert(byte_size(Sid) > 0),

  %% Resume: provider asserts it sees previous_response_id=resp_2.
  erlang:erase(openagentic_test_step_prev),
  {ok, _Out2} =
    openagentic_runtime:query(
      <<"again">>,
      #{
        session_root => Root,
        resume_session_id => Sid,
        provider_mod => openagentic_testing_provider_prev,
        tools => [openagentic_tool_echo],
        api_key => <<"x">>,
        model => <<"x">>
      }
    ),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_runtime_resume_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
