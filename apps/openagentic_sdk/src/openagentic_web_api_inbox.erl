-module(openagentic_web_api_inbox).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  Status = query_bin(Req0, <<"status">>),
  Input =
    case Status of
      undefined -> #{};
      _ -> #{status => Status}
    end,
  case openagentic_case_store:list_inbox(SessionRoot, Input) of
    {ok, Mail} -> reply_json(200, #{mail => Mail}, Req0, State);
    {error, Reason} -> reply_json(500, #{error => to_bin(Reason)}, Req0, State)
  end.

query_bin(Req0, Name) ->
  case lists:keyfind(Name, 1, cowboy_req:parse_qs(Req0)) of
    {_, <<>>} -> undefined;
    {_, Value} -> Value;
    false -> undefined
  end.

reply_json(Status, Obj0, Req0, State) ->
  Obj = ensure_map(Obj0),
  Body = openagentic_json:encode_safe(Obj),
  Req1 = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>, <<"cache-control">> => <<"no-store">>}, Body, Req0),
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
