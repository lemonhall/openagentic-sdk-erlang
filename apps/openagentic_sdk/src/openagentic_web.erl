-module(openagentic_web).

-export([start/1, stop/0, base_url/1]).

%% Minimal Cowboy-based web UI server (local-first).
%%
%% - Serves static UI from `apps/openagentic_sdk/priv/web`
%% - Exposes JSON APIs to start workflows and answer HITL prompts
%% - Streams workflow session events via SSE by tailing `events.jsonl`

-define(DEFAULT_BIND, "127.0.0.1").
-define(DEFAULT_PORT, 8088).

start(Opts0) ->
  Opts = ensure_map(Opts0),
  ok = ensure_cowboy_started(),
  ok = ensure_runtime_started(),

  Bind0 = ensure_list(maps:get(web_bind, Opts, maps:get(bind, Opts, ?DEFAULT_BIND))),
  Bind1 = string:trim(Bind0),
  Bind =
    case Bind1 of
      "" -> ?DEFAULT_BIND;
      "undefined" -> ?DEFAULT_BIND;
      _ -> Bind1
    end,
  Port = int_or_default(maps:get(web_port, Opts, maps:get(port, Opts, ?DEFAULT_PORT)), ?DEFAULT_PORT),
  ProjectDir = ensure_list(maps:get(project_dir, Opts, ".")),
  SessionRoot = ensure_list(maps:get(session_root, Opts, openagentic_paths:default_session_root())),

  WebDir = priv_web_dir(ProjectDir),

  State =
    #{
      project_dir => ProjectDir,
      session_root => SessionRoot,
      web_dir => WebDir,
      runtime_opts => Opts
    },

  Dispatch =
    cowboy_router:compile([
      {'_', [
        {"/", openagentic_web_static, State},
        {"/assets/[...]", openagentic_web_static, State},
        {"/api/cases", openagentic_web_api_cases_create, State},
        {"/api/cases/:case_id/overview", openagentic_web_api_cases_overview, State},
        {"/api/cases/:case_id/candidates/extract", openagentic_web_api_candidates_extract, State},
        {"/api/cases/:case_id/candidates/:candidate_id/approve", openagentic_web_api_candidates_approve, State},
        {"/api/cases/:case_id/candidates/:candidate_id/discard", openagentic_web_api_candidates_discard, State},
        {"/api/cases/:case_id/tasks/:task_id/detail", openagentic_web_api_tasks_detail, State},
        {"/api/cases/:case_id/tasks/:task_id/credential-bindings", openagentic_web_api_task_credential_bindings, State},
        {"/api/cases/:case_id/tasks/:task_id/activate", openagentic_web_api_tasks_activate, State},
        {"/api/workflows/start", openagentic_web_api_workflows_start, State},
        {"/api/workflows/continue", openagentic_web_api_workflows_continue, State},
        {"/api/workflows/cancel", openagentic_web_api_workflows_cancel, State},
        {"/api/workspace/read", openagentic_web_api_workspace_read, State},
        {"/api/questions/answer", openagentic_web_api_questions_answer, State},
        {"/api/sessions/:sid/query", openagentic_web_api_sessions_query, State},
        {"/api/sessions/:sid/events", openagentic_web_api_sse, State},
        {"/api/health", openagentic_web_api_health, State},
        {"/view/[...]", openagentic_web_static, State}
      ]}
    ]),

  case cowboy:start_clear(openagentic_web_listener, [{ip, parse_ip(Bind)}, {port, Port}], #{env => #{dispatch => Dispatch}}) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok;
    Other -> erlang:error({cowboy_listener_start_failed, Other})
  end,
  {ok, #{bind => Bind, port => Port, url => base_url(#{bind => Bind, port => Port})}}.

stop() ->
  catch cowboy:stop_listener(openagentic_web_listener),
  ok.

base_url(#{bind := Bind0, port := Port}) ->
  Bind = ensure_list(Bind0),
  case Bind of
    "0.0.0.0" -> iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port), <<"/">>]);
    "localhost" -> iolist_to_binary([<<"http://localhost:">>, integer_to_binary(Port), <<"/">>]);
    "undefined" -> iolist_to_binary([<<"http://127.0.0.1:">>, integer_to_binary(Port), <<"/">>]);
    _ -> iolist_to_binary([<<"http://">>, iolist_to_binary(Bind), <<":">>, integer_to_binary(Port), <<"/">>])
  end.

ensure_cowboy_started() ->
  case application:ensure_all_started(cowboy) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok;
    Other -> erlang:error({cowboy_start_failed, Other})
  end.

ensure_runtime_started() ->
  case openagentic_web_runtime_sup:ensure_started() of
    {ok, _Pid} -> ok;
    {error, {already_started, _Pid}} -> ok;
    Other -> erlang:error({web_runtime_start_failed, Other})
  end.

priv_web_dir(ProjectDir0) ->
  ProjectDir = ensure_list(ProjectDir0),
  case code:priv_dir(openagentic_sdk) of
    {error, _} ->
      filename:join([ProjectDir, "apps", "openagentic_sdk", "priv", "web"]);
    Dir ->
      filename:join([ensure_list(Dir), "web"])
  end.

parse_ip(Bind) ->
  case inet:parse_address(ensure_list(Bind)) of
    {ok, Ip} -> Ip;
    _ -> {127, 0, 0, 1}
  end.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
