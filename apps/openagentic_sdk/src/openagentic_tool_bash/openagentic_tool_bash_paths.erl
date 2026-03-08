-module(openagentic_tool_bash_paths).

-export([normalize_posix_paths_to_windows/1]).

normalize_posix_paths_to_windows(Text0) ->
  Text = openagentic_tool_bash_utils:to_bin(Text0),
  case os:type() of
    {win32, _} ->
      T1 = replace_wsl_paths(Text),
      replace_msys_paths(T1);
    _ ->
      Text
  end.

replace_wsl_paths(Bin) ->
  replace_paths(Bin, wsl, 0, []).

replace_msys_paths(Bin) ->
  replace_paths(Bin, msys, 0, []).

replace_paths(Bin, Type, Pos0, Acc0) ->
  case find_path(Bin, Type, Pos0) of
    none ->
      Tail = binary:part(Bin, Pos0, byte_size(Bin) - Pos0),
      iolist_to_binary(lists:reverse([Tail | Acc0]));
    {Start, End, Repl} ->
      Prefix = binary:part(Bin, Pos0, Start - Pos0),
      replace_paths(Bin, Type, End, [Repl, Prefix | Acc0])
  end.

find_path(Bin, wsl, Pos0) ->
  Size = byte_size(Bin),
  case binary:match(Bin, <<"/mnt/">>, [{scope, {Pos0, Size - Pos0}}]) of
    nomatch -> none;
    {Pos, _} -> resolve_wsl_path(Bin, Pos, Size)
  end;
find_path(Bin, msys, Pos0) ->
  Size = byte_size(Bin),
  case binary:match(Bin, <<"/">>, [{scope, {Pos0, Size - Pos0}}]) of
    nomatch -> none;
    {Pos, _} -> resolve_msys_path(Bin, Pos, Size)
  end.

resolve_wsl_path(Bin, Pos, Size) ->
  case path_prefix_ok(Bin, Pos) andalso (Pos + 6 < Size) of
    false -> find_path(Bin, wsl, Pos + 1);
    true ->
      Drive = binary:at(Bin, Pos + 5),
      Slash = binary:at(Bin, Pos + 6),
      case is_alpha(Drive) andalso Slash =:= $/ of
        false -> find_path(Bin, wsl, Pos + 1);
        true ->
          RestStart = Pos + 7,
          End = scan_path_end(Bin, RestStart),
          Rest = binary:part(Bin, RestStart, End - RestStart),
          {Pos, End, win_path(Drive, Rest)}
      end
  end.

resolve_msys_path(Bin, Pos, Size) ->
  case path_prefix_ok(Bin, Pos) andalso (Pos + 2 < Size) of
    false -> find_path(Bin, msys, Pos + 1);
    true ->
      Drive = binary:at(Bin, Pos + 1),
      Slash = binary:at(Bin, Pos + 2),
      case is_alpha(Drive) andalso Slash =:= $/ of
        false -> find_path(Bin, msys, Pos + 1);
        true ->
          case binary:part(Bin, Pos, erlang:min(5, Size - Pos)) of
            <<"/mnt/">> -> find_path(Bin, msys, Pos + 1);
            _ ->
              RestStart = Pos + 3,
              End = scan_path_end(Bin, RestStart),
              Rest = binary:part(Bin, RestStart, End - RestStart),
              {Pos, End, win_path(Drive, Rest)}
          end
      end
  end.

path_prefix_ok(_Bin, 0) -> true;
path_prefix_ok(Bin, Pos) when Pos > 0 ->
  Prev = binary:at(Bin, Pos - 1),
  lists:member(Prev, [$\s, $\t, $\r, $\n, $', $\", $(]).

scan_path_end(Bin, Index) ->
  scan_path_end2(Bin, Index, byte_size(Bin)).

scan_path_end2(_Bin, Index, Size) when Index >= Size -> Size;
scan_path_end2(Bin, Index, Size) ->
  Char = binary:at(Bin, Index),
  case lists:member(Char, [$\s, $\t, $\r, $\n, $', $\", $(, $)]) of
    true -> Index;
    false -> scan_path_end2(Bin, Index + 1, Size)
  end.

is_alpha(Char) when Char >= $a, Char =< $z -> true;
is_alpha(Char) when Char >= $A, Char =< $Z -> true;
is_alpha(_) -> false.

win_path(DriveChar, Rest0) ->
  Drive = string:uppercase(<<DriveChar>>),
  Rest = binary:replace(Rest0, <<"/">>, <<"\\">>, [global]),
  <<Drive/binary, ":\\", Rest/binary>>.
