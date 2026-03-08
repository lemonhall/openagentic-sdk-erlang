-module(openagentic_workflow_engine_test_utils).

-include_lib("eunit/include/eunit.hrl").

-export([test_root/0, write_file/2, last_run_start_step_id/1, last_step_output/2, find_first_event/2, find_last_event/2, ensure_map/1, ensure_list_value/1, to_bin/1, find_step_by_id/2, assert_prompt_has_staging_constraints/2]).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_workflow_engine_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "workflows", "prompts", "x"])),
  Tmp.

write_file(Path, Bin) ->
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  file:write_file(Path, Bin).

last_run_start_step_id(Events0) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case maps:get(<<"type">>, E, <<>>) of
        <<"workflow.run.start">> -> maps:get(<<"start_step_id">>, E, Best0);
        _ -> Best0
      end
    end,
    <<>>,
    Events
  ).

last_step_output(Events0, StepId0) ->
  Events = ensure_list_value(Events0),
  StepId = to_bin(StepId0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case maps:get(<<"type">>, E, <<>>) of
        <<"workflow.step.output">> ->
          case maps:get(<<"step_id">>, E, <<>>) of
            StepId -> maps:get(<<"output">>, E, Best0);
            _ -> Best0
          end;
        _ ->
          Best0
      end
    end,
    <<>>,
    Events
  ).

find_first_event(Events0, Type0) ->
  Events = ensure_list_value(Events0),
  Type = to_bin(Type0),
  case [E || E <- Events, maps:get(<<"type">>, ensure_map(E), <<>>) =:= Type] of
    [H | _] -> H;
    [] -> #{}
  end.

find_last_event(Events0, Type0) ->
  Events = ensure_list_value(Events0),
  Type = to_bin(Type0),
  case lists:reverse([E || E <- Events, maps:get(<<"type">>, ensure_map(E), <<>>) =:= Type]) of
    [H | _] -> H;
    [] -> #{}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(B) when is_binary(B) -> [B];
ensure_list_value(undefined) -> [];
ensure_list_value(null) -> [];
ensure_list_value(Other) -> [Other].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

find_step_by_id(_Id, []) ->
  erlang:error(step_not_found);
find_step_by_id(Id, [#{<<"id">> := Id} = Step | _]) ->
  Step;
find_step_by_id(Id, [_ | Rest]) ->
  find_step_by_id(Id, Rest).

assert_prompt_has_staging_constraints(Path, Ministry) ->
  {ok, Bin} = file:read_file(Path),
  ?assert(binary:match(Bin, iolist_to_binary([<<"workspace:staging/">>, Ministry, <<"/poem.md">>])) =/= nomatch),
  ?assert(binary:match(Bin, iolist_to_binary([<<"workspace:staging/">>, Ministry, <<"/...">>])) =/= nomatch),
  ?assertEqual(nomatch, binary:match(Bin, <<"workspace:deliverables/">>)).
