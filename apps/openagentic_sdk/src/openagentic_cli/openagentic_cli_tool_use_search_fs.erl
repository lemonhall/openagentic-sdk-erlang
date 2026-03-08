-module(openagentic_cli_tool_use_search_fs).
-export([tool_use_summary/2]).

tool_use_summary(<<"WebSearch">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Q =
    string:trim(
      openagentic_cli_values:to_bin(
        openagentic_cli_values:first_non_blank([
          maps:get(<<"query">>, Input, undefined),
          maps:get(query, Input, undefined),
          maps:get(<<"q">>, Input, undefined),
          maps:get(q, Input, undefined)
        ])
      )
    ),
  MR = maps:get(<<"max_results">>, Input, maps:get(max_results, Input, undefined)),
  Q2 = openagentic_cli_tool_output_utils:truncate_bin(Q, 120),
  case {byte_size(Q2) > 0, MR} of
    {true, undefined} -> iolist_to_binary([<<" q=\"">>, Q2, <<"\"">>]);
    {true, _} -> iolist_to_binary([<<" q=\"">>, Q2, <<"\" max_results=">>, openagentic_cli_values:to_bin(MR)]);
    _ -> <<>>
  end;
tool_use_summary(<<"WebFetch">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Url = string:trim(openagentic_cli_values:to_bin(maps:get(<<"url">>, Input, maps:get(url, Input, <<>>)))),
  Mode = string:trim(openagentic_cli_values:to_bin(maps:get(<<"mode">>, Input, maps:get(mode, Input, <<>>)))),
  Url2 = openagentic_cli_tool_output_utils:truncate_bin(Url, 160),
  Mode2 = openagentic_cli_tool_output_utils:truncate_bin(Mode, 40),
  case byte_size(Url2) > 0 of
    true ->
      case byte_size(Mode2) > 0 of
        true -> iolist_to_binary([<<" url=">>, Url2, <<" mode=">>, Mode2]);
        false -> iolist_to_binary([<<" url=">>, Url2])
      end;
    false -> <<>>
  end;
tool_use_summary(<<"Read">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  P =
    string:trim(
      openagentic_cli_values:to_bin(
        openagentic_cli_values:first_non_blank([
          maps:get(<<"file_path">>, Input, undefined),
          maps:get(file_path, Input, undefined),
          maps:get(<<"filePath">>, Input, undefined),
          maps:get(filePath, Input, undefined),
          maps:get(<<"path">>, Input, undefined),
          maps:get(path, Input, undefined)
        ])
      )
    ),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<" file_path=">>, openagentic_cli_tool_output_utils:truncate_bin(P, 140)]); false -> <<>> end;
tool_use_summary(<<"List">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  P =
    string:trim(
      openagentic_cli_values:to_bin(
        openagentic_cli_values:first_non_blank([
          maps:get(<<"path">>, Input, undefined),
          maps:get(path, Input, undefined),
          maps:get(<<"dir">>, Input, undefined),
          maps:get(dir, Input, undefined),
          maps:get(<<"directory">>, Input, undefined),
          maps:get(directory, Input, undefined)
        ])
      )
    ),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<" path=">>, openagentic_cli_tool_output_utils:truncate_bin(P, 140)]); false -> <<>> end;
tool_use_summary(<<"Glob">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Pattern = string:trim(openagentic_cli_values:to_bin(maps:get(<<"pattern">>, Input, maps:get(pattern, Input, <<>>)))),
  Root = string:trim(openagentic_cli_values:to_bin(openagentic_cli_values:first_non_blank([maps:get(<<"root">>, Input, undefined), maps:get(root, Input, undefined), maps:get(<<"path">>, Input, undefined), maps:get(path, Input, undefined)]))),
  P2 = openagentic_cli_tool_output_utils:safe_preview(Pattern, 140),
  R2 = openagentic_cli_tool_output_utils:safe_preview(Root, 140),
  case {byte_size(P2) > 0, byte_size(R2) > 0} of
    {true, true} -> iolist_to_binary([<<" pattern=\"">>, P2, <<"\" root=">>, R2]);
    {true, false} -> iolist_to_binary([<<" pattern=\"">>, P2, <<"\"">>]);
    _ -> <<>>
  end;
tool_use_summary(<<"Grep">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Query = string:trim(openagentic_cli_values:to_bin(maps:get(<<"query">>, Input, maps:get(query, Input, <<>>)))),
  Root = string:trim(openagentic_cli_values:to_bin(openagentic_cli_values:first_non_blank([maps:get(<<"root">>, Input, undefined), maps:get(root, Input, undefined), maps:get(<<"path">>, Input, undefined), maps:get(path, Input, undefined)]))),
  FileGlob = string:trim(openagentic_cli_values:to_bin(maps:get(<<"file_glob">>, Input, maps:get(file_glob, Input, <<>>)))),
  Mode = string:trim(openagentic_cli_values:to_bin(maps:get(<<"mode">>, Input, maps:get(mode, Input, <<>>)))),
  Q2 = openagentic_cli_tool_output_utils:safe_preview(Query, 120),
  R2 = openagentic_cli_tool_output_utils:safe_preview(Root, 140),
  G2 = openagentic_cli_tool_output_utils:safe_preview(FileGlob, 80),
  M2 = openagentic_cli_tool_output_utils:safe_preview(Mode, 40),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Q2) > 0 -> iolist_to_binary([<<" q=\"">>, Q2, <<"\"">>]); true -> <<>> end,
        if byte_size(R2) > 0 -> iolist_to_binary([<<" root=">>, R2]); true -> <<>> end,
        if byte_size(G2) > 0 -> iolist_to_binary([<<" file_glob=">>, G2]); true -> <<>> end,
        if byte_size(M2) > 0 -> iolist_to_binary([<<" mode=">>, M2]); true -> <<>> end
      ]
    )
  ).
