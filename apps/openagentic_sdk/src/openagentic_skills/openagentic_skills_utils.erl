-module(openagentic_skills_utils).

-export([ensure_list/1, nthtail_safe/2, to_bin/1, trim/1]).

trim(Bin) -> trim_left(trim_right(Bin)).

trim_left(<<" ", Rest/binary>>) -> trim_left(Rest);
trim_left(<<"	", Rest/binary>>) -> trim_left(Rest);
trim_left(Bin) -> Bin.

trim_right(Bin) ->
  Size = byte_size(Bin),
  case Size of
    0 -> <<>>;
    _ ->
      case binary:at(Bin, Size - 1) of
        $\s -> trim_right(binary:part(Bin, 0, Size - 1));
        $	 -> trim_right(binary:part(Bin, 0, Size - 1));
        $ -> trim_right(binary:part(Bin, 0, Size - 1));
        _ -> Bin
      end
  end.

ensure_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
ensure_list(List) when is_list(List) -> List;
ensure_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> iolist_to_binary(List);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

nthtail_safe(N, List) when N =< 0 -> List;
nthtail_safe(_N, []) -> [];
nthtail_safe(N, [_ | Tail]) -> nthtail_safe(N - 1, Tail).
