-module(openagentic_permissions_policy).

-export([safe_tools/0, safe_schema_ok/2, is_workspace_write_tool_allowed/3]).

safe_tools() ->
  [
    <<"List">>,
    <<"Read">>,
    <<"Glob">>,
    <<"Grep">>,
    <<"WebFetch">>,
    <<"WebSearch">>,
    <<"Skill">>,
    <<"SlashCommand">>,
    <<"AskUserQuestion">>
  ].

safe_schema_ok(<<"Read">>, Input) ->
  non_empty_string_any(Input, [<<"file_path">>, <<"filePath">>, file_path, filePath]);
safe_schema_ok(<<"List">>, Input) ->
  non_empty_string_any(Input, [<<"path">>, path, <<"dir">>, dir, <<"directory">>, directory]);
safe_schema_ok(<<"Glob">>, Input) ->
  non_empty_string_any(Input, [<<"pattern">>, pattern]);
safe_schema_ok(<<"Grep">>, Input) ->
  non_empty_string_any(Input, [<<"query">>, query]);
safe_schema_ok(<<"WebFetch">>, Input) ->
  non_empty_string_any(Input, [<<"url">>, url]);
safe_schema_ok(<<"WebSearch">>, Input) ->
  non_empty_string_any(Input, [<<"query">>, query, <<"q">>, q]);
safe_schema_ok(_, _Input) ->
  true.

non_empty_string_any(Map, Keys) ->
  lists:any(
    fun (K) ->
      case maps:get(K, Map, undefined) of
        undefined -> false;
        V ->
          Bin = openagentic_permissions_utils:to_bin(V),
          byte_size(string:trim(Bin)) > 0
      end
    end,
    Keys
  ).

is_workspace_write_tool_allowed(<<"Write">>, ToolInput0, Context0) ->
  P0 = workspace_write_path(ToolInput0),
  is_workspace_scoped_path(P0) orelse is_workspace_scoped_path_by_resolution(P0, Context0);
is_workspace_write_tool_allowed(<<"Edit">>, ToolInput0, Context0) ->
  P0 = workspace_write_path(ToolInput0),
  is_workspace_scoped_path(P0) orelse is_workspace_scoped_path_by_resolution(P0, Context0);
is_workspace_write_tool_allowed(_, _ToolInput, _Context) ->
  false.

workspace_write_path(ToolInput0) ->
  ToolInput = openagentic_permissions_utils:ensure_map(ToolInput0),
  openagentic_permissions_utils:first_non_blank([
    maps:get(<<"file_path">>, ToolInput, undefined),
    maps:get(file_path, ToolInput, undefined),
    maps:get(<<"filePath">>, ToolInput, undefined),
    maps:get(filePath, ToolInput, undefined)
  ]).

is_workspace_scoped_path(undefined) -> false;
is_workspace_scoped_path(null) -> false;
is_workspace_scoped_path(false) -> false;
is_workspace_scoped_path(P0) ->
  P = string:trim(openagentic_permissions_utils:to_bin(P0)),
  openagentic_permissions_utils:starts_with(P, <<"workspace:">>) orelse
    openagentic_permissions_utils:starts_with(P, <<"ws:">>).

is_workspace_scoped_path_by_resolution(undefined, _Context) -> false;
is_workspace_scoped_path_by_resolution(null, _Context) -> false;
is_workspace_scoped_path_by_resolution(false, _Context) -> false;
is_workspace_scoped_path_by_resolution(P0, Context0) ->
  Context = openagentic_permissions_utils:ensure_map(Context0),
  WorkspaceDir = openagentic_permissions_utils:first_non_blank([
    maps:get(workspace_dir, Context, undefined),
    maps:get(workspaceDir, Context, undefined),
    maps:get(<<"workspace_dir">>, Context, undefined),
    maps:get(<<"workspaceDir">>, Context, undefined)
  ]),
  case WorkspaceDir of
    undefined ->
      false;
    _ ->
      P = string:trim(openagentic_permissions_utils:to_bin(P0)),
      case byte_size(P) of
        0 -> false;
        _ ->
          case openagentic_fs:resolve_write_path(WorkspaceDir, P) of
            {ok, _Abs} -> true;
            _ -> false
          end
      end
  end.
