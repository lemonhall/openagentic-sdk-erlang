-module(openagentic_web_api_workspace_read).

-behaviour(cowboy_handler).

-include_lib("kernel/include/file.hrl").

-export([init/2]).

-define(MAX_BYTES, 2097152). %% 2 MiB

init(Req0, State0) ->
  State = ensure_map(State0),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),
  {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
  Body = string:trim(BodyBin),
  case decode_json(Body) of
    {ok, Obj} ->
      WfSid = to_bin(maps:get(<<"workflow_session_id">>, Obj, maps:get(<<"workflowSessionId">>, Obj, <<>>))),
      Path = to_bin(maps:get(<<"path">>, Obj, <<>>)),
      case {byte_size(string:trim(WfSid)) > 0, byte_size(string:trim(Path)) > 0} of
        {false, _} ->
          reply_json(400, #{error => <<"missing workflow_session_id">>}, Req1, State);
        {_, false} ->
          reply_json(400, #{error => <<"missing path">>}, Req1, State);
        {true, true} ->
          handle_read(SessionRoot, WfSid, Path, Req1, State)
      end;
    {error, _} ->
      reply_json(400, #{error => <<"invalid json">>}, Req1, State)
  end.

handle_read(SessionRoot0, WfSid0, Path0, Req0, State) ->
  SessionRoot = ensure_list(SessionRoot0),
  WfSid = to_bin(WfSid0),
  Path = to_bin(Path0),
  case workspace_rel(Path) of
    {ok, Rel} ->
      case openagentic_fs:is_safe_rel_path(Rel) of
        false ->
          reply_json(404, #{error => <<"not found">>}, Req0, State);
        true ->
          case session_workspace_dir(SessionRoot, WfSid) of
            {ok, WorkspaceDir} ->
              Full = filename:join([WorkspaceDir, ensure_list(Rel)]),
              case file:read_file_info(Full) of
                {ok, FI} ->
                  case FI#file_info.size > ?MAX_BYTES of
                    true ->
                      reply_json(413, #{error => <<"file too large">>}, Req0, State);
                    false ->
                      case file:read_file(Full) of
                        {ok, Bin} ->
                          Resp =
                            #{
                              ok => true,
                              workflow_session_id => WfSid,
                              path => Path,
                              rel_path => to_bin(Rel),
                              bytes => FI#file_info.size,
                              content_type => content_type(Rel),
                              content => Bin
                            },
                          reply_json(200, Resp, Req0, State);
                        _ ->
                          reply_json(404, #{error => <<"not found">>}, Req0, State)
                      end
                  end;
                _ ->
                  reply_json(404, #{error => <<"not found">>}, Req0, State)
              end;
            error ->
              reply_json(404, #{error => <<"not found">>}, Req0, State)
          end
      end;
    {error, _} ->
      reply_json(404, #{error => <<"not found">>}, Req0, State)
  end.

session_workspace_dir(SessionRoot0, WfSid0) ->
  SessionRoot = ensure_list(SessionRoot0),
  WfSid = ensure_list(WfSid0),
  try
    Dir = openagentic_session_store:session_dir(SessionRoot, WfSid),
    {ok, filename:join([Dir, "workspace"])}
  catch
    _:_ -> error
  end.

workspace_rel(Path0) ->
  Path = string:trim(to_bin(Path0)),
  Prefix = <<"workspace:">>,
  case Path of
    <<Prefix:10/binary, Rest/binary>> ->
      Rel0 = string:trim(Rest),
      Rel =
        case Rel0 of
          <<"/", R/binary>> -> R;
          _ -> Rel0
        end,
      case byte_size(Rel) > 0 of
        true -> {ok, Rel};
        false -> {error, empty}
      end;
    _ ->
      {error, not_workspace}
  end.

content_type(Rel0) ->
  Rel = ensure_list(Rel0),
  case filename:extension(Rel) of
    ".md" -> <<"text/markdown; charset=utf-8">>;
    ".markdown" -> <<"text/markdown; charset=utf-8">>;
    ".txt" -> <<"text/plain; charset=utf-8">>;
    ".json" -> <<"application/json; charset=utf-8">>;
    _ -> <<"text/plain; charset=utf-8">>
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
