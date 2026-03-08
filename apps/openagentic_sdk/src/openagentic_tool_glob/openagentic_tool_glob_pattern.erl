-module(openagentic_tool_glob_pattern).

-export([should_early_exit_after_first_match/1, resolve_scan_roots/2]).

should_early_exit_after_first_match(PatternRaw0) ->
  PatternRaw = openagentic_tool_glob_utils:ensure_list(PatternRaw0),
  Pattern = normalize_pattern(PatternRaw),
  Components = [C || C <- string:split(Pattern, "/", all), C =/= ""],
  case Components of
    ["**", Name] ->
      Name2 = string:trim(Name),
      case Name2 of
        "" -> false;
        "**" -> false;
        _ ->
          HasWild =
            string:find(Name2, "*") =/= nomatch orelse
            string:find(Name2, "?") =/= nomatch orelse
            string:find(Name2, "[") =/= nomatch,
          case HasWild of
            true -> false;
            false -> string:find(Name2, "/") =:= nomatch
          end
      end;
    _ ->
      false
  end.

resolve_scan_roots(BaseDir0, PatternRaw0) ->
  BaseDir = openagentic_tool_glob_utils:ensure_list(BaseDir0),
  Pattern = normalize_pattern(openagentic_tool_glob_utils:ensure_list(PatternRaw0)),
  case Pattern of
    "" -> [BaseDir];
    "**/*" -> [BaseDir];
    _ -> resolve_pattern_scan_roots(BaseDir, Pattern)
  end.

normalize_pattern(PatternRaw) ->
  Pattern1 = string:trim(lists:flatten(string:replace(PatternRaw, "\\", "/", all))),
  case Pattern1 of
    [$/ | Tail1] -> Tail1;
    _ -> Pattern1
  end.

resolve_pattern_scan_roots(BaseDir, Pattern) ->
  Components = [C || C <- string:split(Pattern, "/", all), C =/= ""],
  FixedPrefix = lists:takewhile(fun is_fixed_segment/1, Components),
  case FixedPrefix of
    [] ->
      [BaseDir];
    _ ->
      PrefixDir = filename:join(FixedPrefix),
      case openagentic_fs:is_safe_rel_path(PrefixDir) of
        false ->
          [BaseDir];
        true ->
          resolve_prefix_path(BaseDir, PrefixDir, Components, FixedPrefix)
      end
  end.

is_fixed_segment(Seg) ->
  Seg =/= "**" andalso
    string:find(Seg, "*") =:= nomatch andalso
    string:find(Seg, "?") =:= nomatch andalso
    string:find(Seg, "[") =:= nomatch.

resolve_prefix_path(BaseDir, PrefixDir, Components, FixedPrefix) ->
  PrefixPath = filename:join([BaseDir, PrefixDir]),
  case filelib:is_dir(PrefixPath) of
    false ->
      [];
    true ->
      Remaining = lists:nthtail(length(FixedPrefix), Components),
      resolve_remaining_scan_roots(PrefixPath, Remaining)
  end.

resolve_remaining_scan_roots(PrefixPath, [First, _Second | _]) ->
  IsDirGlob =
    First =/= "**" andalso
      (string:find(First, "*") =/= nomatch orelse
        string:find(First, "?") =/= nomatch orelse
        string:find(First, "[") =/= nomatch),
  case IsDirGlob of
    true -> expand_globbed_dirs(PrefixPath, First);
    false -> [PrefixPath]
  end;
resolve_remaining_scan_roots(PrefixPath, _Remaining) ->
  [PrefixPath].

expand_globbed_dirs(PrefixPath, First) ->
  DirRe = openagentic_glob:to_re(First),
  Expanded =
    case file:list_dir(PrefixPath) of
      {ok, Names} ->
        [
          filename:join([PrefixPath, openagentic_tool_glob_utils:ensure_list(Name)])
          || Name <- Names,
             filelib:is_dir(filename:join([PrefixPath, openagentic_tool_glob_utils:ensure_list(Name)])),
             re:run(openagentic_tool_glob_utils:ensure_list(Name), DirRe, [{capture, none}]) =:= match
        ];
      _ ->
        []
    end,
  case Expanded of
    [] -> [PrefixPath];
    _ -> Expanded
  end.
