-module(openagentic_fs).

-export([resolve_project_path/2, resolve_tool_path/2, is_safe_rel_path/1, norm_abs/1, norm_abs_bin/1]).

%% Resolve a user-provided relative path against a project directory.
%% Denies absolute paths, drive-letter paths, and traversal ("..") segments.
resolve_project_path(ProjectDir0, RelPath0) ->
  ProjectDir = ensure_list(ProjectDir0),
  RelPath = ensure_list(RelPath0),
  case is_safe_rel_path(RelPath) of
    false ->
      {error, unsafe_path};
    true ->
      {ok, filename:join([ProjectDir, RelPath])}
  end.

%% Resolve a user-provided path (absolute or project-root-relative) against a project directory.
%% Denies any path that ends up outside the project root.
resolve_tool_path(ProjectDir0, RawPath0) ->
  ProjectDir = ensure_list(ProjectDir0),
  RawPath = ensure_list(RawPath0),
  Stripped = string:trim(RawPath),
  case Stripped of
    "" ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"tool path must be non-empty">>}};
    _ ->
      FullPath =
        case has_drive_prefix(Stripped) orelse is_abs(Stripped) of
          true ->
            abs_norm(Stripped);
          false ->
            abs_norm(filename:join([ProjectDir, Stripped]))
        end,
      FullNative = filename:nativename(FullPath),
      RootNorm = norm_abs_cmp(ProjectDir),
      RootShown = norm_abs_bin(ProjectDir),
      RootNoSlash =
        case RootNorm of
          [] -> [];
          _ ->
            case lists:last(RootNorm) of
              $/ -> lists:sublist(RootNorm, length(RootNorm) - 1);
              _ -> RootNorm
            end
        end,
      RootPrefix = RootNoSlash ++ "/",
      FullNorm = norm_abs_cmp(FullNative),
      case (FullNorm =:= RootNoSlash) orelse lists:prefix(RootPrefix, FullNorm) of
        true -> {ok, FullNative};
        false -> {error, {kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"Tool path must be under project root: ">>, RootShown])}}
      end
  end.

is_safe_rel_path(Path0) ->
  Path = ensure_list(Path0),
  Stripped = string:trim(Path),
  case Stripped of
    "" ->
      false;
    _ ->
      %% Reject obvious absolute / drive paths on Windows.
      case has_drive_prefix(Stripped) orelse is_abs(Stripped) of
        true -> false;
        false ->
          Segs = filename:split(Stripped),
          lists:all(fun seg_ok/1, Segs)
      end
  end.

norm_abs(Path0) ->
  Path = ensure_list(Path0),
  Abs0 = abs_norm(Path),
  lists:flatten(string:replace(Abs0, "\\", "/", all)).

norm_abs_bin(Path0) ->
  iolist_to_binary(norm_abs(Path0)).

%% comparisons: normalize + lowercase drive for case-insensitive Windows prefixes
norm_abs_cmp(Path0) ->
  lower_drive(norm_abs(Path0)).

lower_drive([A, $: | Rest]) when A >= $A, A =< $Z ->
  [A + 32, $: | Rest];
lower_drive(Other) ->
  Other.

abs_norm(Path0) ->
  Abs0 = filename:absname(Path0),
  %% Normalize "." and ".." segments so prefix checks can't be bypassed.
  Segs0 = filename:split(Abs0),
  Segs = collapse_segs(Segs0, []),
  filename:join(Segs).

collapse_segs([], AccRev) ->
  lists:reverse(AccRev);
collapse_segs(["." | Rest], AccRev) ->
  collapse_segs(Rest, AccRev);
collapse_segs([".." | Rest], AccRev) ->
  case AccRev of
    [] ->
      collapse_segs(Rest, AccRev);
    [Drive | Tail] ->
      case is_drive_seg(Drive) of
        true ->
          %% Don't pop past the drive/root segment.
          collapse_segs(Rest, [Drive | Tail]);
        false ->
          collapse_segs(Rest, Tail)
      end
  end;
collapse_segs([Seg | Rest], AccRev) ->
  collapse_segs(Rest, [Seg | AccRev]).

is_drive_seg([A, $:]) when A >= $A, A =< $Z -> true;
is_drive_seg([A, $:]) when A >= $a, A =< $z -> true;
is_drive_seg(_) -> false.

has_drive_prefix([A, $: | _]) when A >= $A, A =< $Z -> true;
has_drive_prefix([A, $: | _]) when A >= $a, A =< $z -> true;
has_drive_prefix(_) -> false.

is_abs([$\\, $\\ | _]) -> true; %% UNC path
is_abs([$/ | _]) -> true;
is_abs([$\\ | _]) -> true;
is_abs(_) -> false.

seg_ok("..") -> false;
seg_ok(".") -> true;
seg_ok("") -> true;
seg_ok(S) ->
  %% deny null bytes etc.
  not lists:member(0, S).

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
