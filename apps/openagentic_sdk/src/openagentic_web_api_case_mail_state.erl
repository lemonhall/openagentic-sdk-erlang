-module(openagentic_web_api_case_mail_state).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  CaseId = cowboy_req:binding(case_id, Req0),
  MailId = cowboy_req:binding(mail_id, Req0),
  Action = cowboy_req:binding(action, Req0),
  {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
  case decode_json(BodyBin) of
    {ok, Obj0} ->
      Status =
        case Action of
          <<"read">> -> <<"read">>;
          <<"archive">> -> <<"archived">>;
          _ -> <<"read">>
        end,
      Payload = (ensure_map(Obj0))#{case_id => CaseId, mail_id => MailId, status => Status},
      case openagentic_case_store:update_mail_state(SessionRoot, Payload) of
        {ok, Mail} -> reply_json(200, #{mail => Mail}, Req1, State);
        {error, {missing_required_field, Field}} -> reply_json(400, #{error => <<"missing required field">>, field => to_bin(Field)}, Req1, State);
        {error, {revision_conflict, CurrentRevision}} -> reply_json(409, #{error => <<"revision_conflict">>, current_revision => CurrentRevision}, Req1, State);
        {error, not_found} -> reply_json(404, #{error => <<"not found">>}, Req1, State);
        {error, Reason} -> reply_json(500, #{error => to_bin(Reason)}, Req1, State)
      end;
    {error, _} ->
      reply_json(400, #{error => <<"invalid json">>}, Req1, State)
  end.

decode_json(<<>>) -> {ok, #{}};
decode_json(Bin) ->
  try
    {ok, openagentic_json:decode(Bin)}
  catch
    _:_ -> {error, invalid}
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
