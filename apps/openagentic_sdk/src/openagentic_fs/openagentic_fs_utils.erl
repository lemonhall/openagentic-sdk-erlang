-module(openagentic_fs_utils).

-export([ensure_list/1]).

ensure_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
ensure_list(List) when is_list(List) -> List;
ensure_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
