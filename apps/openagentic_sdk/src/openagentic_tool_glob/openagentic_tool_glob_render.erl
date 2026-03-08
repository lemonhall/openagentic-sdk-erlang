-module(openagentic_tool_glob_render).

-export([render_stop/4]).

render_stop(BaseDir, Pattern, Matches0, Stop) ->
  BaseNorm = openagentic_fs:norm_abs_bin(BaseDir),
  Matches = lists:sort(Matches0),
  Out0 = #{
    root => BaseNorm,
    matches => Matches,
    pattern => openagentic_tool_glob_utils:to_bin(Pattern),
    count => length(Matches)
  },
  case Stop of
    {max_scanned_paths, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok, Out0#{
        search_path => SearchPath,
        truncated => true,
        stopped_early => true,
        early_exit_reason => <<"max_scanned_paths">>
      }};
    {first_match, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok, Out0#{
        search_path => SearchPath,
        truncated => true,
        stopped_early => true,
        early_exit_reason => <<"first_match">>
      }};
    {max_matches, SearchPath0} ->
      SearchPath = openagentic_fs:norm_abs_bin(SearchPath0),
      {ok, Out0#{search_path => SearchPath, truncated => true}}
  end.
