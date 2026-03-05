-module(openagentic_web_api_workflows_cancel).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
  Body = string:trim(BodyBin),
  case decode_json(Body) of
    {ok, Obj} ->
      WfSid = to_bin(maps:get(<<"workflow_session_id">>, Obj, maps:get(<<"workflowSessionId">>, Obj, <<>>))),
      case byte_size(string:trim(WfSid)) > 0 of
        false ->
          reply_json(400, #{error => <<"missing workflow_session_id">>}, Req1, State);
        true ->
          case openagentic_workflow_mgr:cancel_workflow(SessionRoot, WfSid) of
            {ok, Res} ->
              reply_json(200, ensure_map(Res), Req1, State);
            {error, Reason} ->
              reply_json(500, #{error => to_bin(Reason)}, Req1, State)
          end
      end;
    {error, _} ->
      reply_json(400, #{error => <<"invalid json">>}, Req1, State)
  end.

decode_json(<<>>) -> {error, empty};
decode_json(Bin) ->
  try
    {ok, openagentic_json:decode(Bin)}
  catch
    _:_ -> {error, invalid}
  end.

reply_json(Status, Obj0, Req0, State) ->
  Obj = ensure_map(Obj0),
  Body = openagentic_json:encode_safe(Obj),
  Req1 =
    cowboy_req:reply(
      Status,
      #{<<"content-type">> => <<"application/json">>, <<"cache-control">> => <<"no-store">>},
      Body,
      Req0
    ),
  {ok, Req1, State}.

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

