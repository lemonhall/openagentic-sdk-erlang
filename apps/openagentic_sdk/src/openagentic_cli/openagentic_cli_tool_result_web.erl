-module(openagentic_cli_tool_result_web).
-export([tool_result_lines/2]).

tool_result_lines(<<"WebSearch">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Total = maps:get(total_results, Output, maps:get(<<"total_results">>, Output, undefined)),
  Results0 = maps:get(results, Output, maps:get(<<"results">>, Output, [])),
  Results = openagentic_cli_values:ensure_list(Results0),
  Head =
    case Total of
      undefined -> <<"WebSearch results">>;
      _ -> iolist_to_binary([<<"WebSearch results total=">>, openagentic_cli_values:to_bin(Total)])
    end,
  Items =
    lists:sublist(
      [
        openagentic_cli_tool_output_utils:websearch_result_line(R)
      ||
        R0 <- Results,
        R <- [openagentic_cli_values:ensure_map(R0)],
        byte_size(string:trim(openagentic_cli_values:to_bin(maps:get(url, R, maps:get(<<"url">>, R, <<>>))))) > 0
      ],
      3
    ),
  [Head | Items];
tool_result_lines(<<"WebFetch">>, Output0) ->
  Output = openagentic_cli_values:ensure_map(Output0),
  Status = maps:get(status, Output, maps:get(<<"status">>, Output, undefined)),
  Url = maps:get(url, Output, maps:get(<<"url">>, Output, maps:get(final_url, Output, maps:get(<<"final_url">>, Output, <<>>)))),
  Title = maps:get(title, Output, maps:get(<<"title">>, Output, <<>>)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  Line1 =
    iolist_to_binary([
      <<"WebFetch">>,
      case Status of undefined -> <<>>; _ -> iolist_to_binary([<<" status=">>, openagentic_cli_values:to_bin(Status)]) end,
      case byte_size(string:trim(openagentic_cli_values:to_bin(Tr))) > 0 of false -> <<>>; true -> iolist_to_binary([<<" truncated=">>, openagentic_cli_values:to_bin(Tr)]) end
    ]),
  Line2 =
    case byte_size(string:trim(openagentic_cli_values:to_bin(Url))) > 0 of
      true -> iolist_to_binary([<<"url=">>, openagentic_cli_tool_output_utils:truncate_bin(openagentic_cli_values:to_bin(Url), 200)]);
      false -> <<>>
    end,
  Line3 =
    case byte_size(string:trim(openagentic_cli_values:to_bin(Title))) > 0 of
      true -> iolist_to_binary([<<"title=">>, openagentic_cli_tool_output_utils:truncate_bin(openagentic_cli_values:to_bin(Title), 200)]);
      false -> <<>>
    end,
  [L || L <- [Line1, Line2, Line3], byte_size(string:trim(openagentic_cli_values:to_bin(L))) > 0].
