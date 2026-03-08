-module(openagentic_tool_grep_walk).

-export([grep_walk/4]).

grep_walk(RootDir0, DecideFun, AccFun, Acc0) ->
  RootDir = openagentic_tool_grep_utils:ensure_list(RootDir0),
  walk_dir(RootDir, RootDir, DecideFun, AccFun, Acc0).

walk_dir(Dir, RootDir, DecideFun, AccFun, Acc0) ->
  Children =
    case file:list_dir(Dir) of
      {ok, Names} -> lists:sort(Names);
      _ -> []
    end,
  lists:foldl(
    fun (Name0, Acc1) ->
      Name = openagentic_tool_grep_utils:ensure_list(Name0),
      Full = filename:join([Dir, Name]),
      case filelib:is_dir(Full) of
        true -> walk_dir(Full, RootDir, DecideFun, AccFun, Acc1);
        false ->
          Rel = openagentic_glob:relpath(RootDir, Full),
          case DecideFun(Full, Rel) of
            {skip, _} -> Acc1;
            {hit, Hit} -> AccFun(Hit, Acc1);
            {scan, ScanPath} -> AccFun(ScanPath, Acc1)
          end
      end
    end,
    Acc0,
    Children
  ).
