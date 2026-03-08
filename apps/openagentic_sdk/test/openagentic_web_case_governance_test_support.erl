-module(openagentic_web_case_governance_test_support).

-export([append_round_result/3, reset_web_runtime/0, maybe_kill/1, ensure_httpc_started/0, http_post_json/2, http_get_json/1, http_get_text/1, contains_codepoints/2, deep_get_bin/2, deep_get_int/2, tmp_root/0, pick_port/0, ensure_map/1, ensure_list/1, to_bin/1]).

append_round_result(Root, Sid, FinalText) ->
  {ok, _} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:workflow_done(<<"wf_case">>, <<"governance">>, <<"completed">>, FinalText, #{})
    ),
  ok.

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

http_get_json(Url0) ->
  Url = ensure_list(Url0),
  Headers = [{"accept", "application/json"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} = httpc:request(get, {Url, Headers}, HttpOptions, Opts),
  {Status, openagentic_json:decode(RespBody)}.

http_get_text(Url0) ->
  Url = ensure_list(Url0),
  Headers = [{"accept", "text/html"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} = httpc:request(get, {Url, Headers}, HttpOptions, Opts),
  Text =
    case unicode:characters_to_list(RespBody, utf8) of
      L when is_list(L) -> L;
      _ -> ensure_list(RespBody)
    end,
  {Status, Text}.

contains_codepoints(Text, Codepoints) ->
  string:find(Text, unicode:characters_to_list(Codepoints)) =/= nomatch.

deep_get_bin(Map0, [Key]) -> to_bin(maps:get(Key, Map0));
deep_get_bin(Map0, [Key | Rest]) -> deep_get_bin(maps:get(Key, Map0), Rest).

deep_get_int(Map0, [Key]) -> maps:get(Key, Map0);
deep_get_int(Map0, [Key | Rest]) -> deep_get_int(maps:get(Key, Map0), Rest).

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_web_case_governance_test", Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

pick_port() ->
  case gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}, binary, {active, false}]) of
    {ok, Sock} ->
      {ok, {_Ip, Port}} = inet:sockname(Sock),
      ok = gen_tcp:close(Sock),
      Port;
    _ ->
      18090
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
