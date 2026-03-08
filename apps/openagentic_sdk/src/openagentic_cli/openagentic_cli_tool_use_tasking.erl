-module(openagentic_cli_tool_use_tasking).
-export([tool_use_summary/2]).

tool_use_summary(<<"lsp">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Op = string:trim(openagentic_cli_values:to_bin(maps:get(<<"operation">>, Input, maps:get(operation, Input, <<>>)))),
  File =
    string:trim(
      openagentic_cli_values:to_bin(
        openagentic_cli_values:first_non_blank([
          maps:get(<<"filePath">>, Input, undefined),
          maps:get(filePath, Input, undefined),
          maps:get(<<"file_path">>, Input, undefined),
          maps:get(file_path, Input, undefined)
        ])
      )
    ),
  Line = maps:get(<<"line">>, Input, maps:get(line, Input, undefined)),
  Ch = maps:get(<<"character">>, Input, maps:get(character, Input, undefined)),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Op) > 0 -> iolist_to_binary([<<" operation=">>, openagentic_cli_tool_output_utils:safe_preview(Op, 60)]); true -> <<>> end,
        if byte_size(File) > 0 -> iolist_to_binary([<<" file=">>, openagentic_cli_tool_output_utils:safe_preview(File, 160)]); true -> <<>> end,
        case {Line, Ch} of
          {undefined, _} -> <<>>;
          {_, undefined} -> iolist_to_binary([<<" line=">>, openagentic_cli_values:to_bin(Line)]);
          _ -> iolist_to_binary([<<" pos=">>, openagentic_cli_values:to_bin(Line), <<":">>, openagentic_cli_values:to_bin(Ch)])
        end
      ]
    )
  );
tool_use_summary(<<"TodoWrite">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Todos = maps:get(<<"todos">>, Input, maps:get(todos, Input, [])),
  case is_list(Todos) of
    true -> iolist_to_binary([<<" todos=">>, integer_to_binary(length(Todos))]);
    false -> <<>>
  end;
tool_use_summary(<<"Task">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Agent = string:trim(openagentic_cli_values:to_bin(maps:get(<<"agent">>, Input, maps:get(agent, Input, <<>>)))),
  Prompt = string:trim(openagentic_cli_values:to_bin(maps:get(<<"prompt">>, Input, maps:get(prompt, Input, <<>>)))),
  A2 = openagentic_cli_tool_output_utils:safe_preview(Agent, 40),
  P2 = openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_tool_output_utils:redact_secrets(Prompt), 140),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(A2) > 0 -> iolist_to_binary([<<" agent=">>, A2]); true -> <<>> end,
        if byte_size(P2) > 0 -> iolist_to_binary([<<" prompt=\"">>, P2, <<"\"">>]); true -> <<>> end
      ]
    )
  );
tool_use_summary(_Other, _Input) ->
  <<>>.
