-module(openagentic_web_api_workflows_start).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  Opts0 = ensure_map(maps:get(runtime_opts, State, #{})),
  ProjectDir = ensure_list(maps:get(project_dir, State, ".")),
  SessionRoot = ensure_list(maps:get(session_root, State, openagentic_paths:default_session_root())),

  {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
  Body = string:trim(BodyBin),
  case decode_json(Body) of
    {ok, Obj} ->
      Prompt = to_bin(maps:get(<<"prompt">>, Obj, <<>>)),
      Dsl0 = to_bin(maps:get(<<"dsl">>, Obj, <<"workflows/three-provinces-six-ministries.v1.json">>)),
      Dsl =
        case string:trim(Dsl0) of
          <<>> -> <<"workflows/three-provinces-six-ministries.v1.json">>;
          V -> V
        end,
      case byte_size(string:trim(Prompt)) > 0 of
        false ->
          reply_json(400, #{error => <<"missing prompt">>}, Req1, State);
        true ->
          EngineOpts0 =
            Opts0#{
              project_dir => ProjectDir,
              cwd => ProjectDir,
              session_root => SessionRoot,
              %% Enable web HITL via openagentic_web_q broker.
              web_hil => true,
              strict_unknown_fields => true
            },
          case openagentic_workflow_mgr:start_workflow(ProjectDir, ensure_list(Dsl), Prompt, EngineOpts0) of
            {ok, Res0} ->
              Res = ensure_map(Res0),
              WfId = maps:get(workflow_id, Res, <<>>),
              WfSid = maps:get(workflow_session_id, Res, <<>>),
              WfDir = openagentic_session_store:session_dir(SessionRoot, ensure_list(WfSid)),
              WorkspaceDir = filename:join([WfDir, "workspace"]),
              Resp =
                #{
                  workflow_id => WfId,
                  workflow_session_id => WfSid,
                  workspace_dir => openagentic_fs:norm_abs_bin(WorkspaceDir),
                  events_url => iolist_to_binary([<<"/api/sessions/">>, to_bin(WfSid), <<"/events">>]),
                  queued => maps:get(queued, Res, false),
                  queue_length => maps:get(queue_length, Res, 0),
                  status => to_bin(maps:get(status, Res, <<"running">>)),
                  resumed_from_stalled => maps:get(resumed_from_stalled, Res, false)
                },
              reply_json(201, Resp, Req1, State);
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
