-module(openagentic_tool_grep_api).

-include_lib("kernel/include/file.hrl").

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_grep_utils:ensure_map(Input0),
  Ctx = openagentic_tool_grep_utils:ensure_map(Ctx0),
  ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  WorkspaceDir0 = maps:get(workspace_dir, Ctx, maps:get(workspaceDir, Ctx, [])),
  case validated_query(Input) of
    {error, Err} -> {error, Err};
    {ok, Query} -> run_with_query(Input, ProjectDir0, WorkspaceDir0, Query)
  end.

validated_query(Input) ->
  case maps:get(<<"query">>, Input, maps:get(query, Input, undefined)) of
    undefined -> query_required_error();
    Query0 ->
      Query = openagentic_tool_grep_utils:to_bin(Query0),
      case byte_size(string:trim(Query)) > 0 of
        true -> {ok, Query};
        false -> query_required_error()
      end
  end.

query_required_error() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Grep: 'query' must be a non-empty string">>}}.

run_with_query(Input, ProjectDir0, WorkspaceDir0, Query) ->
  FileGlob = file_glob(Input),
  RootRaw = root_raw(Input),
  case resolve_root(ProjectDir0, WorkspaceDir0, RootRaw) of
    {error, Reason} -> {error, Reason};
    {ok, RootDir0} ->
      RootDir = openagentic_tool_grep_utils:ensure_list(RootDir0),
      case validate_root_dir(RootDir) of
        ok -> compile_and_run(Input, Query, FileGlob, RootDir);
        {error, Err} -> {error, Err}
      end
  end.

file_glob(Input) ->
  FileGlob0 = maps:get(<<"file_glob">>, Input, maps:get(file_glob, Input, <<"**/*">>)),
  case string:trim(openagentic_tool_grep_utils:to_bin(FileGlob0)) of
    <<>> -> <<"**/*">>;
    FileGlob -> FileGlob
  end.

root_raw(Input) ->
  case openagentic_tool_grep_utils:first_non_empty(Input, [<<"root">>, root, <<"path">>, path]) of
    undefined -> <<>>;
    RootRaw0 -> string:trim(openagentic_tool_grep_utils:to_bin(RootRaw0))
  end.

resolve_root(ProjectDir0, WorkspaceDir0, RootRaw) when byte_size(RootRaw) > 0 ->
  openagentic_fs:resolve_read_path(ProjectDir0, WorkspaceDir0, RootRaw);
resolve_root(ProjectDir0, WorkspaceDir0, _RootRaw) ->
  openagentic_fs:resolve_read_path(ProjectDir0, WorkspaceDir0, ".").

validate_root_dir(RootDir) ->
  case file:read_file_info(RootDir) of
    {ok, Info} when Info#file_info.type =:= directory -> ok;
    {ok, _Info} ->
      Msg = iolist_to_binary([<<"Grep: not a directory: ">>, openagentic_fs:norm_abs_bin(RootDir)]),
      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}};
    {error, enoent} ->
      Msg = iolist_to_binary([<<"Grep: not found: ">>, openagentic_fs:norm_abs_bin(RootDir)]),
      {error, {kotlin_error, <<"FileNotFoundException">>, Msg}};
    {error, Reason} ->
      Msg = iolist_to_binary([<<"Grep: cannot access root: ">>, openagentic_fs:norm_abs_bin(RootDir), <<" error=">>, openagentic_tool_grep_utils:to_bin(Reason)]),
      {error, {kotlin_error, <<"RuntimeException">>, Msg}}
  end.

compile_and_run(Input, Query, FileGlob, RootDir) ->
  CaseSensitive = openagentic_tool_grep_utils:bool_opt(Input, [<<"case_sensitive">>, case_sensitive], true) =/= false,
  IncludeHidden = openagentic_tool_grep_utils:bool_opt(Input, [<<"include_hidden">>, include_hidden], true) =/= false,
  Mode0 = maps:get(<<"mode">>, Input, maps:get(mode, Input, <<"content">>)),
  Mode = string:trim(openagentic_tool_grep_utils:to_bin(Mode0)),
  BeforeN = openagentic_tool_grep_utils:int_opt(Input, [<<"before_context">>, before_context], 0),
  AfterN = openagentic_tool_grep_utils:int_opt(Input, [<<"after_context">>, after_context], 0),
  case validate_grep_inputs(Mode, BeforeN, AfterN) of
    ok -> compile_pattern(Query, FileGlob, RootDir, IncludeHidden, Mode, BeforeN, AfterN, CaseSensitive);
    {kotlin_error, Msg} -> {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}}
  end.

compile_pattern(Query, FileGlob, RootDir, IncludeHidden, Mode, BeforeN, AfterN, CaseSensitive) ->
  ReOpts = case CaseSensitive of true -> []; false -> [caseless] end,
  case re:compile(Query, ReOpts) of
    {ok, QueryRe} ->
      FileGlobRe = openagentic_glob:to_re(FileGlob),
      openagentic_tool_grep_search:do_grep(Query, QueryRe, FileGlobRe, RootDir, IncludeHidden, Mode, BeforeN, AfterN);
    {error, Err} ->
      Msg = openagentic_tool_grep_utils:pattern_syntax_message(Query, Err),
      {error, {kotlin_error, <<"PatternSyntaxException">>, Msg}}
  end.

validate_grep_inputs(Mode, BeforeN, AfterN) ->
  case {Mode, BeforeN, AfterN} of
    {<<>>, _, _} -> {kotlin_error, <<"Grep: 'mode' must be a string">>};
    {_, B, _} when not is_integer(B); B < 0 -> {kotlin_error, <<"Grep: 'before_context' must be a non-negative integer">>};
    {_, _, A} when not is_integer(A); A < 0 -> {kotlin_error, <<"Grep: 'after_context' must be a non-negative integer">>};
    _ -> ok
  end.
