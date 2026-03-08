-module(openagentic_tool_schemas_utils).

-export([ensure_list/1, ensure_map/1, norm_bin/1, to_bin/1]).

ensure_map(Map) when is_map(Map) -> Map;
ensure_map(List) when is_list(List) -> maps:from_list(List);
ensure_map(_) -> #{}.

norm_bin(Path0) ->
  Path = ensure_list(Path0),
  iolist_to_binary(string:replace(filename:absname(Path), "\\", "/", all)).

ensure_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
ensure_list(List) when is_list(List) -> List;
ensure_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> iolist_to_binary(List);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Int) when is_integer(Int) -> iolist_to_binary(integer_to_list(Int));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
