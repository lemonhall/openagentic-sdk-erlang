-module(openagentic_runtime_paths).
-export([ensure_workspace_dir/3,default_workspace_dir/2,file_get_cwd_safe/0]).

ensure_workspace_dir(RootDir0, SessionId0, WorkspaceDirOpt0) ->
  RootDir = openagentic_runtime_utils:ensure_list(RootDir0),
  SessionId = SessionId0,
  case WorkspaceDirOpt0 of
    undefined ->
      default_workspace_dir(RootDir, SessionId);
    null ->
      default_workspace_dir(RootDir, SessionId);
    <<>> ->
      default_workspace_dir(RootDir, SessionId);
    "" ->
      default_workspace_dir(RootDir, SessionId);
    <<"undefined">> ->
      default_workspace_dir(RootDir, SessionId);
    "undefined" ->
      default_workspace_dir(RootDir, SessionId);
    V ->
      openagentic_runtime_utils:ensure_list(V)
  end.

default_workspace_dir(RootDir, SessionId) ->
  Dir = openagentic_session_store:session_dir(RootDir, SessionId),
  filename:join([Dir, "workspace"]).

file_get_cwd_safe() ->
  case file:get_cwd() of
    {ok, V} -> V;
    _ -> "."
  end.
