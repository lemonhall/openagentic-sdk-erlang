-module(openagentic_anthropic_parsing_input).

-export([responses_input_to_messages/1]).

responses_input_to_messages(Input0) ->
  Input = openagentic_anthropic_parsing_utils:ensure_list(Input0),
  responses_input_loop(Input, #{system_parts => [], messages => [], pending_role => <<>>, pending_blocks => []}).

responses_input_loop([], Acc0) ->
  Acc1 = flush_pending(Acc0),
  System = join_system(maps:get(system_parts, Acc1, [])),
  Messages0 = maps:get(messages, Acc1, []),
  {System, ensure_first_user(Messages0)};
responses_input_loop([Item0 | Rest], Acc0) ->
  Item = openagentic_anthropic_parsing_utils:ensure_map(Item0),
  Role = openagentic_anthropic_parsing_utils:bin_trim(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Type = openagentic_anthropic_parsing_utils:bin_trim(maps:get(type, Item, maps:get(<<"type">>, Item, <<>>))),
  Acc1 =
    case {Role, Type} of
      {<<"system">>, _} -> append_system(Item, Acc0);
      {_, <<"function_call">>} -> append_function_call(Item, Acc0);
      {_, <<"function_call_output">>} -> append_function_result(Item, Acc0);
      {<<"user">>, _} -> append_role_text(<<"user">>, Item, Acc0);
      {<<"assistant">>, _} -> append_role_text(<<"assistant">>, Item, Acc0);
      _ -> Acc0
    end,
  responses_input_loop(Rest, Acc1).

append_system(Item, Acc0) ->
  AccS = flush_pending(Acc0),
  Content = openagentic_anthropic_parsing_utils:bin_trim(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
  case byte_size(Content) > 0 of
    true -> AccS#{system_parts := maps:get(system_parts, AccS, []) ++ [Content]};
    false -> AccS
  end.

append_function_call(Item, Acc0) ->
  CallId = openagentic_anthropic_parsing_utils:bin_trim(
    maps:get(call_id, Item, maps:get(<<"call_id">>, Item, maps:get(callId, Item, maps:get(<<"callId">>, Item, <<>>))))
  ),
  Name = openagentic_anthropic_parsing_utils:bin_trim(maps:get(name, Item, maps:get(<<"name">>, Item, <<>>))),
  ArgsRaw = openagentic_anthropic_parsing_utils:bin_trim(maps:get(arguments, Item, maps:get(<<"arguments">>, Item, <<>>))),
  Block = #{<<"type">> => <<"tool_use">>, <<"id">> => CallId, <<"name">> => Name, <<"input">> => parse_args_to_map(ArgsRaw)},
  append_block(<<"assistant">>, Block, Acc0).

append_function_result(Item, Acc0) ->
  CallId = openagentic_anthropic_parsing_utils:bin_trim(
    maps:get(call_id, Item, maps:get(<<"call_id">>, Item, maps:get(callId, Item, maps:get(<<"callId">>, Item, <<>>))))
  ),
  Output = openagentic_anthropic_parsing_utils:bin_trim(maps:get(output, Item, maps:get(<<"output">>, Item, <<>>))),
  Block = #{<<"type">> => <<"tool_result">>, <<"tool_use_id">> => CallId, <<"content">> => Output},
  append_block(<<"user">>, Block, Acc0).

append_role_text(Role, Item, Acc0) ->
  Content = openagentic_anthropic_parsing_utils:bin_trim(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
  Block = #{<<"type">> => <<"text">>, <<"text">> => Content},
  append_block(Role, Block, Acc0).

flush_pending(Acc0) ->
  Blocks = maps:get(pending_blocks, Acc0, []),
  Role = maps:get(pending_role, Acc0, <<>>),
  case Blocks of
    [] -> Acc0;
    _ ->
      Msg =
        case Blocks of
          [One] ->
            case maps:get(<<"type">>, One, <<>>) of
              <<"text">> -> #{<<"role">> => Role, <<"content">> => maps:get(<<"text">>, One, <<>>)};
              _ -> #{<<"role">> => Role, <<"content">> => Blocks}
            end;
          _ -> #{<<"role">> => Role, <<"content">> => Blocks}
        end,
      Acc0#{messages := maps:get(messages, Acc0, []) ++ [Msg], pending_role := <<>>, pending_blocks := []}
  end.

append_block(Role, Block, Acc0) ->
  PendingRole = maps:get(pending_role, Acc0, <<>>),
  Acc1 = case PendingRole =:= Role of true -> Acc0; false -> flush_pending(Acc0) end,
  Acc1#{pending_role := Role, pending_blocks := maps:get(pending_blocks, Acc1, []) ++ [Block]}.

ensure_first_user([]) -> [];
ensure_first_user([First | Rest]) ->
  Role = openagentic_anthropic_parsing_utils:bin_trim(maps:get(<<"role">>, openagentic_anthropic_parsing_utils:ensure_map(First), <<>>)),
  case Role of
    <<"assistant">> -> [#{<<"role">> => <<"user">>, <<"content">> => <<"(continue)">>} , First | Rest];
    _ -> [First | Rest]
  end.

join_system([]) -> undefined;
join_system(Parts) ->
  Bin = iolist_to_binary(lists:join(<<"\n\n">>, Parts)),
  case byte_size(openagentic_anthropic_parsing_utils:bin_trim(Bin)) > 0 of
    true -> openagentic_anthropic_parsing_utils:bin_trim(Bin);
    false -> undefined
  end.

parse_args_to_map(ArgsRaw0) ->
  ArgsRaw = openagentic_anthropic_parsing_utils:bin_trim(ArgsRaw0),
  case byte_size(ArgsRaw) of
    0 -> #{};
    _ ->
      try openagentic_json:decode(ArgsRaw) of Obj -> openagentic_anthropic_parsing_utils:ensure_map(Obj)
      catch _:_ -> #{} end
  end.
