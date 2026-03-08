-module(openagentic_fs_symlink).

-include_lib("kernel/include/file.hrl").

-export([check_under_root/2]).

check_under_root(ProjectDir, FullNative) ->
  RootNorm = openagentic_fs_normalize:norm_abs_cmp(ProjectDir),
  RootShown = openagentic_fs_normalize:norm_abs_bin(ProjectDir),
  RootNoSlash = strip_trailing_slash(RootNorm),
  RootPrefix = RootNoSlash ++ "/",
  FullNorm = openagentic_fs_normalize:norm_abs_cmp(FullNative),
  case (FullNorm =:= RootNoSlash) orelse lists:prefix(RootPrefix, FullNorm) of
    true ->
      case check_symlink_escape(ProjectDir, FullNative) of
        ok -> {ok, FullNative};
        {error, Reason} -> {error, Reason}
      end;
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"Tool path must be under project root: ">>, RootShown])}}
  end.

strip_trailing_slash([]) -> [];
strip_trailing_slash(Path) ->
  case lists:last(Path) of
    $/ -> lists:sublist(Path, length(Path) - 1);
    _ -> Path
  end.

check_symlink_escape(ProjectDir0, FullNative0) ->
  ProjectDir = openagentic_fs_utils:ensure_list(ProjectDir0),
  FullNative = openagentic_fs_utils:ensure_list(FullNative0),
  case nearest_existing_prefix(FullNative) of
    undefined -> ok;
    Prefix0 ->
      BaseCanon = canonicalize_existing(ProjectDir),
      PrefixCanon = canonicalize_existing(Prefix0),
      case openagentic_fs_normalize:is_under_base(PrefixCanon, BaseCanon) of
        true -> ok;
        false ->
          Msg = iolist_to_binary([<<"Tool path escapes project root via symlink: base=">>, openagentic_fs_normalize:norm_abs_bin(BaseCanon), <<" prefix=">>, openagentic_fs_normalize:norm_abs_bin(PrefixCanon)]),
          {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}}
      end
  end.

nearest_existing_prefix(Path0) ->
  Path = openagentic_fs_utils:ensure_list(Path0),
  nearest_existing_prefix2(filename:absname(Path)).

nearest_existing_prefix2(Path) ->
  case file:read_link_info(Path) of
    {ok, _Info} -> Path;
    _ ->
      Parent = filename:dirname(Path),
      case Parent =:= Path of true -> undefined; false -> nearest_existing_prefix2(Parent) end
  end.

canonicalize_existing(Path0) ->
  Path = openagentic_fs_normalize:abs_norm(openagentic_fs_utils:ensure_list(Path0)),
  canonicalize_segments(filename:split(Path), "").

canonicalize_segments([], Cur) -> case Cur of "" -> "."; _ -> Cur end;
canonicalize_segments([Seg | Rest], Cur0) ->
  Cur = case Cur0 of "" -> Seg; _ -> filename:join([Cur0, Seg]) end,
  case file:read_link_info(Cur) of
    {ok, Info} when Info#file_info.type =:= symlink ->
      case file:read_link(Cur) of
        {ok, Target0} ->
          TargetAbs = openagentic_fs_normalize:abs_norm(resolve_link_target(Cur, Target0)),
          canonicalize_segments(filename:split(TargetAbs) ++ Rest, "");
        _ -> canonicalize_segments(Rest, Cur)
      end;
    _ ->
      canonicalize_segments(Rest, Cur)
  end.

resolve_link_target(LinkPath0, Target0) ->
  LinkPath = openagentic_fs_utils:ensure_list(LinkPath0),
  Target = openagentic_fs_utils:ensure_list(Target0),
  case openagentic_fs_guards:has_drive_prefix(Target) orelse openagentic_fs_guards:is_abs(Target) of
    true -> Target;
    false -> filename:join([filename:dirname(LinkPath), Target])
  end.
