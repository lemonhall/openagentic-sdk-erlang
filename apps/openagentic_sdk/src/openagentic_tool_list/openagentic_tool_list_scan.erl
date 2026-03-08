-module(openagentic_tool_list_scan).

-export([collect_files/2]).

collect_files(Root, Limit) ->
  collect_dir(Root, [], Limit, []).

collect_dir(_Dir, _RelSegs, Limit, Acc) when length(Acc) >= Limit ->
  {Acc, true};
collect_dir(Dir, RelSegs, Limit, Acc0) ->
  case should_ignore(RelSegs) of
    true ->
      {Acc0, length(Acc0) >= Limit};
    false ->
      Children = case file:list_dir(Dir) of {ok, Names} -> lists:sort(Names); _ -> [] end,
      lists:foldl(fun (Name0, AccIn) -> collect_child(Name0, Dir, RelSegs, Limit, AccIn) end, {Acc0, false}, Children)
  end.

collect_child(_Name0, _Dir, _RelSegs, _Limit, {Acc1, true}) ->
  {Acc1, true};
collect_child(Name0, Dir, RelSegs, Limit, {Acc1, false}) ->
  Name = openagentic_tool_list_utils:ensure_list(Name0),
  Full = filename:join([Dir, Name]),
  Rel = RelSegs ++ [Name],
  case should_ignore(Rel) of
    true ->
      {Acc1, false};
    false ->
      case filelib:is_dir(Full) of
        true -> collect_dir(Full, Rel, Limit, Acc1);
        false ->
          case length(Acc1) + 1 >= Limit of
            true -> {[Rel | Acc1], true};
            false -> {[Rel | Acc1], false}
          end
      end
  end.

should_ignore([]) -> false;
should_ignore(Segs) ->
  lists:any(fun (S) -> lists:member(S, ignore_prefixes()) end, Segs).

ignore_prefixes() ->
  [
    "node_modules", "__pycache__", ".git", "dist", "build", "target", "vendor", ".idea",
    ".vscode", ".venv", "venv", "env", ".cache", "coverage", "tmp", "temp"
  ].
