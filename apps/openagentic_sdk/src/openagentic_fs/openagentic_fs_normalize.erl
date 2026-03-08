-module(openagentic_fs_normalize).

-export([abs_norm/1, is_under_base/2, norm_abs/1, norm_abs_bin/1, norm_abs_cmp/1]).

norm_abs(Path0) ->
  Path = openagentic_fs_utils:ensure_list(Path0),
  Abs0 = abs_norm(Path),
  lists:flatten(string:replace(Abs0, "\\", "/", all)).

norm_abs_bin(Path0) -> iolist_to_binary(norm_abs(Path0)).

norm_abs_cmp(Path0) -> lower_drive(norm_abs(Path0)).

lower_drive([A, $: | Rest]) when A >= $A, A =< $Z -> [A + 32, $: | Rest];
lower_drive(Other) -> Other.

abs_norm(Path0) ->
  Abs0 = filename:absname(Path0),
  Segs = collapse_segs(filename:split(Abs0), []),
  filename:join(Segs).

collapse_segs([], AccRev) -> lists:reverse(AccRev);
collapse_segs(["." | Rest], AccRev) -> collapse_segs(Rest, AccRev);
collapse_segs([".." | Rest], AccRev) ->
  case AccRev of
    [] -> collapse_segs(Rest, AccRev);
    [Drive | Tail] ->
      case openagentic_fs_guards:is_drive_seg(Drive) of
        true -> collapse_segs(Rest, [Drive | Tail]);
        false -> collapse_segs(Rest, Tail)
      end
  end;
collapse_segs([Seg | Rest], AccRev) -> collapse_segs(Rest, [Seg | AccRev]).

is_under_base(Child0, Base0) ->
  Child = norm_abs_cmp(openagentic_fs_utils:ensure_list(Child0)),
  Base = norm_abs_cmp(openagentic_fs_utils:ensure_list(Base0)),
  BaseNoSlash =
    case Base of
      [] -> [];
      _ -> case lists:last(Base) of $/ -> lists:sublist(Base, length(Base) - 1); _ -> Base end
    end,
  Prefix = BaseNoSlash ++ "/",
  (Child =:= BaseNoSlash) orelse lists:prefix(Prefix, Child).
