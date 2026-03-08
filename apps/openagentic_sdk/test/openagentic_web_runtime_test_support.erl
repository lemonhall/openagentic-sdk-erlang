-module(openagentic_web_runtime_test_support).
-export([ensure_httpc_started/0, ensure_list/1, find_last_workflow_done/2, http_post_json/2, pick_port/0, reset_web_runtime/0, tmp_root/0, wait_until/2, write_web_workflow/1]).

-include_lib("eunit/include/eunit.hrl").

write_web_workflow(Root) ->
  ok = write_file(filename:join([Root, "workflows", "prompts", "aggregate.md"]), <<"# aggregate prompt\n">>),
  Json =
    openagentic_json:encode(
      #{
        workflow_version => <<"1.0">>,
        name => <<"web_runtime">>,
        steps => [
          #{
            id => <<"aggregate">>,
            role => <<"shangshu">>,
            input => #{type => <<"controller_input">>},
            prompt => #{type => <<"file">>, path => <<"workflows/prompts/aggregate.md">>},
            output_contract => #{type => <<"markdown_sections">>, required => [<<"Summary">>]},
            guards => [],
            on_pass => null,
            on_fail => null,
            max_attempts => 1,
            timeout_seconds => 30
          }
        ]
      }
    ),
  write_file(filename:join([Root, "workflows", "w_web.json"]), <<Json/binary, "\n">>).

find_last_workflow_done(Events0, Status) ->
  Events = ensure_list_value(Events0),
  lists:foldl(
    fun (E0, Best0) ->
      E = ensure_map(E0),
      case {maps:get(<<"type">>, E, <<>>), maps:get(<<"status">>, E, <<>>)} of
        {<<"workflow.done">>, Status} -> E;
        _ -> Best0
      end
    end,
    false,
    Events
  ).

wait_until(Fun, TimeoutMs) ->
  wait_until(Fun, TimeoutMs, erlang:monotonic_time(millisecond)).

wait_until(Fun, TimeoutMs, StartedAt) ->
  case Fun() of
    false ->
      Now = erlang:monotonic_time(millisecond),
      case (Now - StartedAt) >= TimeoutMs of
        true -> ?assert(false);
        false ->
          timer:sleep(100),
          wait_until(Fun, TimeoutMs, StartedAt)
      end;
    undefined ->
      Now = erlang:monotonic_time(millisecond),
      case (Now - StartedAt) >= TimeoutMs of
        true -> ?assert(false);
        false ->
          timer:sleep(100),
          wait_until(Fun, TimeoutMs, StartedAt)
      end;
    Value ->
      Value
  end.

reset_web_runtime() ->
  openagentic_web:stop(),
  maybe_kill(whereis(openagentic_web_runtime_keeper)),
  maybe_kill(whereis(openagentic_web_runtime_sup)),
  maybe_kill(whereis(openagentic_workflow_mgr)),
  maybe_kill(whereis(openagentic_web_q)),
  timer:sleep(100),
  ok.

maybe_kill(Pid) when is_pid(Pid) ->
  catch exit(Pid, kill),
  ok;
maybe_kill(_) ->
  ok.

ensure_httpc_started() ->
  _ = inets:start(),
  case inets:start(httpc) of
    {ok, _Pid} -> ok;
    {error, {already_started, _Pid}} -> ok;
    _ -> ok
  end.

http_post_json(Url0, Body0) ->
  Url = ensure_list(Url0),
  Body = openagentic_json:encode_safe(ensure_map(Body0)),
  Headers = [{"content-type", "application/json"}, {"accept", "application/json"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} =
    httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Opts),
  {Status, openagentic_json:decode(RespBody)}.

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([ensure_list(Cwd), ".tmp", "eunit", "openagentic_web_runtime_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

pick_port() ->
  case gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}, binary, {active, false}]) of
    {ok, Sock} ->
      {ok, {_Ip, Port}} = inet:sockname(Sock),
      ok = gen_tcp:close(Sock),
      Port;
    _ ->
      18089
  end.

write_file(Path, Bin) ->
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  file:write_file(Path, Bin).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(undefined) -> [];
ensure_list_value(null) -> [];
ensure_list_value(Other) -> [Other].

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
