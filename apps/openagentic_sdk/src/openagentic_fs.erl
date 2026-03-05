-module(openagentic_fs).

-include_lib("kernel/include/file.hrl").

-export([
  resolve_project_path/2,
  resolve_tool_path/2,
  resolve_read_path/3,
  resolve_write_path/2,
  is_safe_rel_path/1,
  norm_abs/1,
  norm_abs_bin/1
]).

%% Resolve a path for read-like tools that may access both the project root and a workflow/session workspace.
%%
%% Supported prefixes:
%% - "workspace:" / "ws:" => resolve under WorkspaceDir
%% - "project:"  / "proj:" => resolve under ProjectDir
%%
%% Without a prefix:
%% - absolute paths are allowed only if they are under ProjectDir or WorkspaceDir
%% - relative paths are resolved under ProjectDir
resolve_read_path(ProjectDir0, WorkspaceDir0, RawPath0) ->
  ProjectDir = ensure_list(ProjectDir0),
  WorkspaceDir = ensure_list(WorkspaceDir0),
  RawPath = ensure_list(RawPath0),
  {Scope, Path} = parse_scope_prefix(RawPath),
  case Scope of
    workspace ->
      resolve_tool_path(WorkspaceDir, Path);
    project ->
      resolve_tool_path(ProjectDir, Path);
    auto ->
      case (WorkspaceDir =/= []) andalso (has_drive_prefix(Path) orelse is_abs(Path)) of
        true ->
          case resolve_tool_path(WorkspaceDir, Path) of
            {ok, _} = Ok -> Ok;
            _ -> resolve_tool_path(ProjectDir, Path)
          end;
        false ->
          resolve_tool_path(ProjectDir, Path)
      end
  end.

%% Resolve a path for write-like tools. Writes must stay under WorkspaceDir.
%%
%% Supported prefixes:
%% - "workspace:" / "ws:" => resolve under WorkspaceDir
%% - "project:"  / "proj:" => rejected
%%
%% Without a prefix:
%% - absolute paths are allowed only if they are under WorkspaceDir
%% - relative paths are resolved under WorkspaceDir
resolve_write_path(WorkspaceDir0, RawPath0) ->
  WorkspaceDir = ensure_list(WorkspaceDir0),
  RawPath = ensure_list(RawPath0),
  {Scope, Path} = parse_scope_prefix(RawPath),
  case Scope of
    project ->
      RootShown = norm_abs_bin(WorkspaceDir),
      {error, {kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"Write path must be under workspace root: ">>, RootShown])}};
    _ ->
      resolve_tool_path(WorkspaceDir, Path)
  end.

parse_scope_prefix(Path0) ->
  Path = string:trim(ensure_list(Path0)),
  Lower = string:lowercase(Path),
  case lists:prefix("workspace:", Lower) of
    true ->
      {workspace, string:trim(lists:nthtail(length("workspace:"), Path))};
    false ->
      case lists:prefix("ws:", Lower) of
        true ->
          {workspace, string:trim(lists:nthtail(length("ws:"), Path))};
        false ->
          case lists:prefix("project:", Lower) of
            true ->
              {project, string:trim(lists:nthtail(length("project:"), Path))};
            false ->
              case lists:prefix("proj:", Lower) of
                true ->
                  {project, string:trim(lists:nthtail(length("proj:"), Path))};
                false ->
                  {auto, Path}
              end
          end
      end
  end.

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
        true ->
          case check_symlink_escape(ProjectDir, FullNative) of
            ok ->
              {ok, FullNative};
            {error, Reason} ->
              {error, Reason}
          end;
        false -> {error, {kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"Tool path must be under project root: ">>, RootShown])}}
      end
  end.

check_symlink_escape(ProjectDir0, FullNative0) ->
  ProjectDir = ensure_list(ProjectDir0),
  FullNative = ensure_list(FullNative0),
  case nearest_existing_prefix(FullNative) of
    undefined ->
      ok;
    Prefix0 ->
      BaseCanon = canonicalize_existing(ProjectDir),
      PrefixCanon = canonicalize_existing(Prefix0),
      case is_under_base(PrefixCanon, BaseCanon) of
        true ->
          ok;
        false ->
          Msg =
            iolist_to_binary([
              <<"Tool path escapes project root via symlink: base=">>,
              norm_abs_bin(BaseCanon),
              <<" prefix=">>,
              norm_abs_bin(PrefixCanon)
            ]),
          {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}}
      end
  end.

nearest_existing_prefix(Path0) ->
  Path = ensure_list(Path0),
  Abs = filename:absname(Path),
  nearest_existing_prefix2(Abs).

nearest_existing_prefix2(Path) ->
  case file:read_link_info(Path) of
    {ok, _Info} ->
      Path;
    _ ->
      Parent = filename:dirname(Path),
      case Parent =:= Path of
        true -> undefined;
        false -> nearest_existing_prefix2(Parent)
      end
  end.

canonicalize_existing(Path0) ->
  Path = abs_norm(ensure_list(Path0)),
  Segs = filename:split(Path),
  canonicalize_segments(Segs, "").

canonicalize_segments([], Cur) ->
  case Cur of
    "" -> ".";
    _ -> Cur
  end;
canonicalize_segments([Seg | Rest], Cur0) ->
  Cur =
    case Cur0 of
      "" -> Seg;
      _ -> filename:join([Cur0, Seg])
    end,
  case file:read_link_info(Cur) of
    {ok, Info} when Info#file_info.type =:= symlink ->
      case file:read_link(Cur) of
        {ok, Target0} ->
          TargetAbs = abs_norm(resolve_link_target(Cur, Target0)),
          canonicalize_segments(filename:split(TargetAbs) ++ Rest, "");
        _ ->
          canonicalize_segments(Rest, Cur)
      end;
    _ ->
      canonicalize_segments(Rest, Cur)
  end.

resolve_link_target(LinkPath0, Target0) ->
  LinkPath = ensure_list(LinkPath0),
  Target = ensure_list(Target0),
  case has_drive_prefix(Target) orelse is_abs(Target) of
    true ->
      Target;
    false ->
      filename:join([filename:dirname(LinkPath), Target])
  end.

is_under_base(Child0, Base0) ->
  Child = norm_abs_cmp(ensure_list(Child0)),
  Base = norm_abs_cmp(ensure_list(Base0)),
  BaseNoSlash =
    case Base of
      [] -> [];
      _ ->
        case lists:last(Base) of
          $/ -> lists:sublist(Base, length(Base) - 1);
          _ -> Base
        end
    end,
  Prefix = BaseNoSlash ++ "/",
  (Child =:= BaseNoSlash) orelse lists:prefix(Prefix, Child).

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
