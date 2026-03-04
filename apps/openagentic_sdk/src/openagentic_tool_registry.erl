-module(openagentic_tool_registry).

-export([new/1, get/2, names/1]).

%% registry() is kept as documentation; specs below make it "used" for warnings_as_errors.
-type registry() :: #{tools := [module()]}.

-spec new([module()]) -> registry().
new(Tools) when is_list(Tools) ->
  #{tools => Tools}.

-spec names(registry()) -> [binary()].
names(Registry) ->
  Tools = maps:get(tools, Registry, []),
  [Tool:name() || Tool <- Tools].

-spec get(registry(), any()) -> {ok, module()} | {error, not_found}.
get(Registry, ToolName0) ->
  ToolName = to_bin(ToolName0),
  Tools = maps:get(tools, Registry, []),
  Found =
    lists:filter(
      fun (Tool) ->
        try Tool:name() =:= ToolName
        catch
          _:_ -> false
        end
      end,
      Tools
    ),
  case Found of
    [Tool | _] -> {ok, Tool};
    [] -> {error, not_found}
  end.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
