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
              QueryOpts0 =
                Opts0#{
                  project_dir => ProjectDir,
                  cwd => ProjectDir,
                  session_root => SessionRoot,
                  resume_session_id => Sid,
                  strict_unknown_fields => true,
                  user_answerer => fun (Question) -> openagentic_web_q:ask(Sid, Question) end
                },
              case maybe_attach_governance_context(QueryOpts0, SessionRoot, Obj) of
                {error, not_found} ->
                  reply_json(404, #{error => <<"task not found">>}, Req1, State);
                {ok, QueryOpts} ->
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
              end
          end;
        {error, _} ->
          reply_json(400, #{error => <<"invalid json">>}, Req1, State)
      end
  end.

maybe_attach_governance_context(QueryOpts0, SessionRoot, Obj0) ->
  Obj = ensure_map(Obj0),
  CaseId = trim_bin(find_any(Obj, [case_id, <<"case_id">>, caseId, <<"caseId">>])),
  TaskId = trim_bin(find_any(Obj, [task_id, <<"task_id">>, taskId, <<"taskId">>])),
  case {CaseId, TaskId} of
    {<<>>, _} -> {ok, QueryOpts0};
    {_, <<>>} -> {ok, QueryOpts0};
    _ ->
      case openagentic_case_store:get_task_detail(SessionRoot, CaseId, TaskId) of
        {ok, Detail0} ->
          GovernancePrompt = governance_context_prompt(CaseId, TaskId, Detail0),
          ExistingPrompt = maps:get(system_prompt, QueryOpts0, maps:get(systemPrompt, QueryOpts0, undefined)),
          {ok, QueryOpts0#{system_prompt => append_system_prompt(ExistingPrompt, GovernancePrompt)}};
        {error, _} ->
          {error, not_found}
      end
  end.

append_system_prompt(undefined, Added) -> Added;
append_system_prompt(<<>>, Added) -> Added;
append_system_prompt(Existing, Added) -> iolist_to_binary([to_bin(Existing), <<"\n\n">>, Added]).

governance_context_prompt(CaseId, TaskId, Detail0) ->
  Detail = ensure_map(Detail0),
  Payload =
    #{
      case_id => CaseId,
      task_id => TaskId,
      task => maps:get(task, Detail, #{}),
      authorization => maps:get(authorization, Detail, #{}),
      latest_version_diff => maps:get(latest_version_diff, Detail, #{}),
      failure_stats => maps:get(failure_stats, Detail, #{}),
      historical_version_summary => maps:get(historical_version_summary, Detail, []),
      historical_execution_summary => maps:get(historical_execution_summary, Detail, #{}),
      latest_exception_summary => maps:get(latest_exception_summary, Detail, #{}),
      latest_report_summary => maps:get(latest_report_summary, Detail, #{}),
      recent_rectification_summary => maps:get(recent_rectification_summary, Detail, #{}),
      run_attempts => maps:get(run_attempts, Detail, []),
      fact_reports => maps:get(fact_reports, Detail, [])
    },
  Json = openagentic_json:encode_safe(Payload),
  iolist_to_binary([
    <<"TASK_GOVERNANCE_CONTEXT_V1\n">>,
    <<"Use this task governance context as authoritative state for the current monitoring task. Ground your answer in this context before suggesting next actions.\n">>,
    Json
  ]).

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

trim_bin(undefined) -> <<>>;
trim_bin(null) -> <<>>;
trim_bin(<<"undefined">>) -> <<>>;
trim_bin(Bin0) -> string:trim(to_bin(Bin0)).

find_any(_Map, []) -> undefined;
find_any(Map, [Key | Rest]) ->
  case maps:get(Key, Map, undefined) of
    undefined -> find_any(Map, Rest);
    Value -> Value
  end.
