-module(openagentic_anthropic_parsing_output).

-export([anthropic_content_to_model_output/3]).

anthropic_content_to_model_output(Content0, Usage0, MessageId0) ->
  Content = openagentic_anthropic_parsing_utils:ensure_list(Content0),
  Usage = case Usage0 of M when is_map(M) -> M; _ -> undefined end,
  MessageId = case MessageId0 of undefined -> undefined; V -> openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:to_bin(V)) end,
  {TextParts, ToolCalls} = lists:foldl(fun fold_content_block/2, {[], []}, Content),
  #{assistant_text => iolist_to_binary(TextParts), tool_calls => ToolCalls, response_id => MessageId, usage => Usage}.

fold_content_block(Block0, {TxtAcc0, CallsAcc0}) ->
  Block = openagentic_anthropic_parsing_utils:ensure_map(Block0),
  Type = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(Block, [<<"type">>, type])),
  case Type of
    <<"text">> ->
      Txt = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(Block, [<<"text">>, text])),
      case byte_size(Txt) > 0 of true -> {TxtAcc0 ++ [Txt], CallsAcc0}; false -> {TxtAcc0, CallsAcc0} end;
    <<"tool_use">> ->
      Id = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(Block, [<<"id">>, id])),
      Name = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(Block, [<<"name">>, name])),
      Input = openagentic_anthropic_parsing_utils:ensure_map(openagentic_anthropic_parsing_utils:pick_first(Block, [<<"input">>, input])),
      {TxtAcc0, CallsAcc0 ++ [#{tool_use_id => Id, name => Name, arguments => Input}]};
    _ ->
      {TxtAcc0, CallsAcc0}
  end.
