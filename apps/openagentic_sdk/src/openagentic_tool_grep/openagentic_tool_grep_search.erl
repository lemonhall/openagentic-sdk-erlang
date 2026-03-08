-module(openagentic_tool_grep_search).

-export([do_grep/8]).

do_grep(Query, QueryRe, FileGlobRe, RootDir, IncludeHidden, Mode, BeforeN, AfterN) ->
  RootNorm = openagentic_fs:norm_abs_bin(RootDir),
  case Mode of
    <<"files_with_matches">> ->
      Files0 = grep_files_with_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden),
      Files = lists:sort(Files0),
      {ok, #{root => RootNorm, query => Query, files => Files, count => length(Files)}};
    _ ->
      case grep_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden, BeforeN, AfterN) of
        {truncated, Matches0} ->
          Matches = lists:reverse(Matches0),
          {ok, #{root => RootNorm, query => Query, matches => Matches, truncated => true}};
        {ok, Matches0} ->
          Matches = lists:reverse(Matches0),
          {ok, #{root => RootNorm, query => Query, matches => Matches, truncated => false, total_matches => length(Matches)}}
      end
  end.

grep_files_with_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden) ->
  Acc =
    openagentic_tool_grep_walk:grep_walk(
      RootDir,
      fun (Path, Rel) -> decide_scan(Path, Rel, QueryRe, FileGlobRe, IncludeHidden, files_with_matches) end,
      fun (Hit, Acc0) ->
        case Hit of
          none -> Acc0;
          _ -> ordsets:add_element(Hit, Acc0)
        end
      end,
      ordsets:new()
    ),
  ordsets:to_list(Acc).

grep_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden, BeforeN, AfterN) ->
  try
    Acc =
      openagentic_tool_grep_walk:grep_walk(
        RootDir,
        fun (Path, Rel) -> decide_scan(Path, Rel, QueryRe, FileGlobRe, IncludeHidden, content) end,
        fun (ScanPath, Acc0) -> accumulate_scan(ScanPath, QueryRe, BeforeN, AfterN, Acc0) end,
        []
      ),
    {ok, Acc}
  catch
    throw:{grep_truncated, Acc1} -> {truncated, Acc1}
  end.

decide_scan(Path, Rel, QueryRe, FileGlobRe, IncludeHidden, Mode) ->
  case should_scan(Path, Rel, FileGlobRe, IncludeHidden) of
    false -> {skip, none};
    true when Mode =:= files_with_matches ->
      case openagentic_tool_grep_scan:file_contains_match(Path, QueryRe) of
        true -> {hit, openagentic_fs:norm_abs_bin(Path)};
        false -> {skip, none}
      end;
    true -> {scan, Path}
  end.

should_scan(Path, Rel, FileGlobRe, IncludeHidden) ->
  case openagentic_tool_grep_filters:is_hidden_rel(Rel) andalso not IncludeHidden of
    true -> false;
    false ->
      case openagentic_tool_grep_filters:is_sensitive_rel(Rel) of
        true -> false;
        false ->
          openagentic_tool_grep_filters:file_matches_glob(Rel, FileGlobRe) andalso
            openagentic_tool_grep_filters:file_readable_small(Path)
      end
  end.

accumulate_scan(none, _QueryRe, _BeforeN, _AfterN, Acc0) -> Acc0;
accumulate_scan(ScanPath, QueryRe, BeforeN, AfterN, Acc0) ->
  case openagentic_tool_grep_scan:scan_one_file(ScanPath, QueryRe, BeforeN, AfterN, Acc0) of
    {truncated, Acc1} -> throw({grep_truncated, Acc1});
    {ok, Acc1} -> Acc1
  end.
