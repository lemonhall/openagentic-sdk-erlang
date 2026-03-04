-module(openagentic_tool_grep).

-include_lib("kernel/include/file.hrl").

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Grep">>.

description() -> <<"Search file contents with a regex.">>.

-define(MAX_MATCHES, 5000).
-define(MAX_FILE_BYTES, 2097152). %% 2 MiB

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),

  Query0 = maps:get(<<"query">>, Input, maps:get(query, Input, undefined)),
  case Query0 of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Grep: 'query' must be a non-empty string">>}};
    _ ->
      Query = to_bin(Query0),
      case byte_size(string:trim(Query)) > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Grep: 'query' must be a non-empty string">>}};
        true ->
          FileGlob0 = maps:get(<<"file_glob">>, Input, maps:get(file_glob, Input, <<"**/*">>)),
          FileGlob1 = string:trim(to_bin(FileGlob0)),
          FileGlob = case byte_size(FileGlob1) > 0 of true -> FileGlob1; false -> <<"**/*">> end,
          RootRaw0 = first_non_empty(Input, [<<"root">>, root, <<"path">>, path]),
          RootRaw = case RootRaw0 of undefined -> <<>>; _ -> string:trim(to_bin(RootRaw0)) end,
          RootRes =
            case byte_size(RootRaw) > 0 of
              true -> openagentic_fs:resolve_tool_path(ProjectDir0, RootRaw);
              false -> openagentic_fs:resolve_tool_path(ProjectDir0, ".")
            end,
          case RootRes of
            {error, Reason} ->
              {error, Reason};
            {ok, RootDir0} ->
              RootDir = ensure_list(RootDir0),
              case filelib:is_dir(RootDir) of
                false ->
                  {error, {not_a_directory, openagentic_fs:norm_abs_bin(RootDir)}};
                true ->
                  CaseSensitive = bool_opt(Input, [<<"case_sensitive">>, case_sensitive], true) =/= false,
                  IncludeHidden = bool_opt(Input, [<<"include_hidden">>, include_hidden], true) =/= false,
                  Mode0 = maps:get(<<"mode">>, Input, maps:get(mode, Input, <<"content">>)),
                  Mode = string:trim(to_bin(Mode0)),
                  BeforeN = int_opt(Input, [<<"before_context">>, before_context], 0),
                  AfterN = int_opt(Input, [<<"after_context">>, after_context], 0),
                  case validate_grep_inputs(Mode, BeforeN, AfterN) of
                    ok ->
                      ReOpts = case CaseSensitive of true -> []; false -> [caseless] end,
                      case re:compile(Query, ReOpts) of
                        {ok, QueryRe} ->
                          FileGlobRe = openagentic_glob:to_re(FileGlob),
                          do_grep(Query, QueryRe, FileGlobRe, RootDir, IncludeHidden, Mode, BeforeN, AfterN);
                        {error, Err} ->
                          {error, {invalid_input, {bad_regex, Err}}}
                      end;
                    {kotlin_error, Msg} ->
                      {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}}
                  end
              end
          end
      end
  end.

validate_grep_inputs(Mode, BeforeN, AfterN) ->
  case {Mode, BeforeN, AfterN} of
    {<<>>, _, _} -> {kotlin_error, <<"Grep: 'mode' must be a string">>};
    {_, B, _} when not is_integer(B); B < 0 -> {kotlin_error, <<"Grep: 'before_context' must be a non-negative integer">>};
    {_, _, A} when not is_integer(A); A < 0 -> {kotlin_error, <<"Grep: 'after_context' must be a non-negative integer">>};
    _ -> ok
  end.

do_grep(Query, QueryRe, FileGlobRe, RootDir, IncludeHidden, Mode, BeforeN, AfterN) ->
  RootNorm = openagentic_fs:norm_abs_bin(RootDir),
  case Mode of
    <<"files_with_matches">> ->
      Files0 = grep_files_with_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden),
      Files = lists:sort(Files0),
      {ok, #{
        root => RootNorm,
        query => Query,
        files => Files,
        count => length(Files)
      }};
    _ ->
      case grep_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden, BeforeN, AfterN) of
        {truncated, Matches0} ->
          Matches = lists:reverse(Matches0),
          {ok, #{
            root => RootNorm,
            query => Query,
            matches => Matches,
            truncated => true
          }};
        {ok, Matches0} ->
          Matches = lists:reverse(Matches0),
          {ok, #{
            root => RootNorm,
            query => Query,
            matches => Matches,
            truncated => false,
            total_matches => length(Matches)
          }}
      end
  end.

grep_files_with_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden) ->
  Acc =
    grep_walk(
      RootDir,
      fun (Path, Rel) ->
        case is_hidden_rel(Rel) andalso not IncludeHidden of
          true -> {skip, none};
          false ->
            case file_matches_glob(Rel, FileGlobRe) of
              false -> {skip, none};
              true ->
                case file_readable_small(Path) of
                  false -> {skip, none};
                  true ->
                    case file_contains_match(Path, QueryRe) of
                      true -> {hit, openagentic_fs:norm_abs_bin(Path)};
                      false -> {skip, none}
                    end
                end
            end
        end
      end,
      fun (Hit, Acc2) ->
        case Hit of
          none -> Acc2;
          _ -> ordsets:add_element(Hit, Acc2)
        end
      end,
      ordsets:new()
    ),
  ordsets:to_list(Acc).

grep_matches(QueryRe, FileGlobRe, RootDir, IncludeHidden, BeforeN, AfterN) ->
  try
    Acc =
      grep_walk(
        RootDir,
        fun (Path, Rel) ->
          case is_hidden_rel(Rel) andalso not IncludeHidden of
            true -> {skip, none};
            false ->
              case file_matches_glob(Rel, FileGlobRe) of
                false -> {skip, none};
                true ->
                  case file_readable_small(Path) of
                    false -> {skip, none};
                    true -> {scan, Path}
                  end
              end
          end
        end,
        fun (ScanPath, Acc0) ->
          case ScanPath of
            none ->
              Acc0;
            _ ->
              case scan_one_file(ScanPath, QueryRe, BeforeN, AfterN, Acc0) of
                {truncated, Acc1} -> throw({grep_truncated, Acc1});
                {ok, Acc1} -> Acc1
              end
          end
        end,
        []
      ),
    {ok, Acc}
  catch
    throw:{grep_truncated, Acc1} ->
      {truncated, Acc1}
  end.

scan_one_file(Path, QueryRe, BeforeN, AfterN, Acc0) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case safe_utf8_lines(Bin) of
        {ok, Lines} ->
          AbsPath = openagentic_fs:norm_abs_bin(Path),
          scan_lines(Lines, 1, [], AbsPath, QueryRe, BeforeN, AfterN, Acc0);
        {error, _} ->
          {ok, Acc0}
      end;
    _ ->
      {ok, Acc0}
  end.

scan_lines([], _LineNo, _PrevRev, _AbsPath, _QueryRe, _BeforeN, _AfterN, Acc) ->
  {ok, Acc};
scan_lines([Line0 | Rest], LineNo, PrevRev, AbsPath, QueryRe, BeforeN, AfterN, Acc0) ->
  case length(Acc0) >= ?MAX_MATCHES of
    true ->
      {truncated, Acc0};
    false ->
      Line = trim_cr(Line0),
      case re:run(Line, QueryRe, [{capture, none}]) of
        match ->
          BeforeCtx =
            case BeforeN > 0 of
              true ->
                TakeN = erlang:min(BeforeN, length(PrevRev)),
                Slice = lists:reverse(lists:sublist(PrevRev, TakeN)),
                [to_bin(S) || S <- Slice];
              false ->
                null
            end,
          AfterCtx =
            case AfterN > 0 of
              true ->
                TakeN2 = erlang:min(AfterN, length(Rest)),
                Slice2 = lists:sublist(Rest, TakeN2),
                [to_bin(trim_cr(S)) || S <- Slice2];
              false ->
                null
            end,
          Match = #{
            file_path => AbsPath,
            line => LineNo,
            text => to_bin(Line),
            before_context => BeforeCtx,
            after_context => AfterCtx
          },
          scan_lines(Rest, LineNo + 1, [Line | PrevRev], AbsPath, QueryRe, BeforeN, AfterN, [Match | Acc0]);
        nomatch ->
          scan_lines(Rest, LineNo + 1, [Line | PrevRev], AbsPath, QueryRe, BeforeN, AfterN, Acc0)
      end
  end.

file_contains_match(Path, QueryRe) ->
  case file:read_file(Path) of
    {ok, Bin} ->
      case safe_utf8_lines(Bin) of
        {ok, Lines} ->
          lists:any(fun (L) -> re:run(trim_cr(L), QueryRe, [{capture, none}]) =:= match end, Lines);
        _ ->
          false
      end;
    _ ->
      false
  end.

file_readable_small(Path) ->
  case file:read_file_info(Path) of
    {ok, Info} ->
      Info#file_info.type =:= regular andalso
        (Info#file_info.size =:= undefined orelse Info#file_info.size =< ?MAX_FILE_BYTES);
    _ ->
      false
  end.

file_matches_glob(Rel0, FileGlobRe) ->
  Rel = ensure_list(Rel0),
  re:run(Rel, FileGlobRe, [{capture, none}]) =:= match.

is_hidden_rel(Rel0) ->
  Rel = ensure_list(Rel0),
  Segs = [S || S <- string:split(Rel, "/", all), S =/= ""],
  lists:any(
    fun (S) ->
      case ensure_list(S) of
        [$. | _] -> true;
        _ -> false
      end
    end,
    Segs
  ).

trim_cr(Bin) when is_binary(Bin) ->
  Sz = byte_size(Bin),
  case Sz of
    0 -> Bin;
    _ ->
      RestSz = Sz - 1,
      case Bin of
        <<Rest:RestSz/binary, $\r>> -> Rest;
        _ -> Bin
      end
  end;
trim_cr(L) when is_list(L) ->
  trim_cr(iolist_to_binary(L)).

safe_utf8_lines(Bin0) when is_binary(Bin0) ->
  try
    Text = unicode:characters_to_binary(Bin0, utf8, utf8),
    Raw = binary:split(Text, <<"\n">>, [global]),
    {ok, Raw}
  catch
    _:_ ->
      {error, bad_utf8}
  end.

grep_walk(RootDir0, DecideFun, AccFun, Acc0) ->
  RootDir = ensure_list(RootDir0),
  walk_dir(RootDir, RootDir, DecideFun, AccFun, Acc0).

walk_dir(Dir, RootDir, DecideFun, AccFun, Acc0) ->
  Children =
    case file:list_dir(Dir) of
      {ok, Names} -> lists:sort(Names);
      _ -> []
    end,
  lists:foldl(
    fun (Name0, Acc1) ->
      Name = ensure_list(Name0),
      Full = filename:join([Dir, Name]),
      case filelib:is_dir(Full) of
        true ->
          walk_dir(Full, RootDir, DecideFun, AccFun, Acc1);
        false ->
          Rel = openagentic_glob:relpath(RootDir, Full),
          case DecideFun(Full, Rel) of
            {skip, _} ->
              Acc1;
            {hit, Hit} ->
              AccFun(Hit, Acc1);
            {scan, ScanPath} ->
              AccFun(ScanPath, Acc1)
          end
      end
    end,
    Acc0,
    Children
  ).

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.

bool_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    true -> true;
    false -> false;
    B when is_binary(B) ->
      case string:lowercase(string:trim(B)) of
        <<"true">> -> true;
        <<"false">> -> false;
        _ -> Default
      end;
    L when is_list(L) ->
      case string:lowercase(string:trim(L)) of
        "true" -> true;
        "false" -> false;
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

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
