-module(openagentic_tool_edit_apply).

-export([edit_file/6]).

edit_file(FullPath, Old, New, Count, Before, After) ->
  case file:read_file(FullPath) of
    {ok, Text} ->
      case binary:match(Text, Old) of
        nomatch ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' text not found in file">>}};
        {IdxOld, _} ->
          apply_edit(Text, FullPath, IdxOld, Old, New, Count, Before, After)
      end;
    Err ->
      {error, edit_io_error(FullPath, Err)}
  end.

apply_edit(Text, FullPath, IdxOld, Old, New, Count, Before, After) ->
  case openagentic_tool_edit_anchors:anchors_ok(Text, IdxOld, Before, After) of
    ok ->
      Occ = openagentic_tool_edit_replace:occurrences(Text, Old),
      Replaced =
        case Count of
          0 -> binary:replace(Text, Old, New, [global]);
          _ -> openagentic_tool_edit_replace:replace_n(Text, Old, New, Count)
        end,
      ok = file:write_file(FullPath, Replaced),
      Replacements = if Count =:= 0 -> Occ; true -> erlang:min(Occ, Count) end,
      {ok, #{
        message => <<"Edit applied">>,
        file_path => openagentic_fs:norm_abs_bin(FullPath),
        replacements => Replacements
      }};
    {error, Reason} ->
      {error, Reason}
  end.

edit_io_error(FullPath, Err0) ->
  Abs = openagentic_fs:norm_abs_bin(FullPath),
  Reason = case Err0 of {error, R} -> R; R -> R end,
  case Reason of
    enoent ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Edit: not found: ">>, Abs])};
    enotdir ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Edit: not found: ">>, Abs])};
    eacces ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Edit: access denied: ">>, Abs])};
    _ ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Edit failed: ">>, openagentic_tool_edit_utils:to_bin(Err0)])}
  end.
