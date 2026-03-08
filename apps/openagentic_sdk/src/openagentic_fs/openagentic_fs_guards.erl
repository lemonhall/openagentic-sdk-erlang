-module(openagentic_fs_guards).

-export([has_drive_prefix/1, is_abs/1, is_drive_seg/1, is_safe_rel_path/1]).

is_safe_rel_path(Path0) ->
  Path = openagentic_fs_utils:ensure_list(Path0),
  Stripped = string:trim(Path),
  case Stripped of
    "" -> false;
    _ ->
      case has_drive_prefix(Stripped) orelse is_abs(Stripped) of
        true -> false;
        false -> lists:all(fun seg_ok/1, filename:split(Stripped))
      end
  end.

is_drive_seg([A, $:]) when A >= $A, A =< $Z -> true;
is_drive_seg([A, $:]) when A >= $a, A =< $z -> true;
is_drive_seg(_) -> false.

has_drive_prefix([A, $: | _]) when A >= $A, A =< $Z -> true;
has_drive_prefix([A, $: | _]) when A >= $a, A =< $z -> true;
has_drive_prefix(_) -> false.

is_abs([$\\, $\\ | _]) -> true;
is_abs([$/ | _]) -> true;
is_abs([$\\ | _]) -> true;
is_abs(_) -> false.

seg_ok("..") -> false;
seg_ok(".") -> true;
seg_ok("") -> true;
seg_ok(Segment) -> not lists:member(0, Segment).
