-module(openagentic_web_api_sessions_query).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  Opts0 = ensure_map(maps:get(runtime_opts, State, #{})),
  ProjectDir = ensure_list(maps:get(project_dir, State, ".")),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  Sid = string:trim(to_bin(cowboy_req:binding(sid, Req0))),

  case ensure_existing_session(SessionRoot, Sid) of
    {error, invalid_session_id} ->
      reply_json(400, #{error => <<"invalid session_id">>}, Req0, State);
    {error, session_not_found} ->
      reply_json(404, #{error => <<"session not found">>}, Req0, State);
    {ok, _SessionDir} ->
      {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
      Body = string:trim(BodyBin),
      case decode_json(Body) of
        {ok, Obj} ->
          Msg = to_bin(maps:get(<<"message">>, Obj, maps:get(<<"prompt">>, Obj, maps:get(message, Obj, maps:get(prompt, Obj, <<>>))))),
          case byte_size(string:trim(Msg)) > 0 of
            false ->
              reply_json(400, #{error => <<"missing message">>}, Req1, State);
            true ->
              QueryOpts =
                Opts0#{
                  project_dir => ProjectDir,
                  cwd => ProjectDir,
                  session_root => SessionRoot,
                  resume_session_id => Sid,
                  strict_unknown_fields => true,
                  user_answerer => fun (Question) -> openagentic_web_q:ask(Sid, Question) end
                },
              case openagentic_runtime:query(Msg, QueryOpts) of
                {ok, Res0} ->
                  Res = ensure_map(Res0),
                  SessionId = to_bin(maps:get(session_id, Res, Sid)),
                  reply_json(
                    200,
                    #{
                      session_id => SessionId,
                      final_text => to_bin(maps:get(final_text, Res, <<>>)),
                      events_url => session_events_url(SessionId)
                    },
                    Req1,
                    State
                  );
                {error, {runtime_error, Reason, SessionId0}} ->
                  SessionId = to_bin(SessionId0),
                  reply_json(
                    500,
                    #{
                      error => to_bin(Reason),
                      session_id => SessionId,
                      events_url => session_events_url(SessionId)
                    },
                    Req1,
                    State
                  );
                {error, Reason} ->
                  reply_json(500, #{error => to_bin(Reason), session_id => Sid, events_url => session_events_url(Sid)}, Req1, State)
              end
          end;
        {error, _} ->
          reply_json(400, #{error => <<"invalid json">>}, Req1, State)
      end
  end.

ensure_existing_session(SessionRoot, Sid) ->
  try
    SessionDir = openagentic_session_store:session_dir(SessionRoot, ensure_list(Sid)),
    case filelib:is_dir(SessionDir) of
      true -> {ok, SessionDir};
      false -> {error, session_not_found}
    end
  catch
    error:{invalid_session_id, _} -> {error, invalid_session_id};
    _:_ -> {error, session_not_found}
  end.

session_events_url(Sid0) ->
  Sid = to_bin(Sid0),
  iolist_to_binary([<<"/api/sessions/">>, Sid, <<"/events">>]).

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
