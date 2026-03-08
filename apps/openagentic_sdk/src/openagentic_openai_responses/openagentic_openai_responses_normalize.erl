-module(openagentic_openai_responses_normalize).

-export([parse_assistant_text/1, parse_tool_calls/1, parse_assistant_text_for_test/1, parse_tool_calls_for_test/1]).

parse_assistant_text(OutputItems0) ->
  Items = openagentic_openai_responses_utils:ensure_list(OutputItems0),
  Parts =
    lists:foldl(
      fun (Item0, Acc) ->
        Item = openagentic_openai_responses_utils:ensure_map(Item0),
        case openagentic_openai_responses_utils:to_bin(maps:get(<<"type">>, Item, maps:get(type, Item, <<>>))) of
          <<"message">> ->
            Content = maps:get(<<"content">>, Item, maps:get(content, Item, [])),
            Acc ++ message_text_parts(Content);
          _ ->
            Acc
        end
      end,
      [],
      Items
    ),
  iolist_to_binary(Parts).

message_text_parts(Content0) ->
  Content = openagentic_openai_responses_utils:ensure_list(Content0),
  lists:foldl(
    fun (Part0, Acc) ->
      Part = openagentic_openai_responses_utils:ensure_map(Part0),
      case openagentic_openai_responses_utils:to_bin(maps:get(<<"type">>, Part, maps:get(type, Part, <<>>))) of
        <<"output_text">> ->
          Txt = maps:get(<<"text">>, Part, maps:get(text, Part, <<>>)),
          case Txt of
            <<>> -> Acc;
            _ -> Acc ++ [openagentic_openai_responses_utils:to_bin(Txt)]
          end;
        _ ->
          Acc
      end
    end,
    [],
    Content
  ).

parse_tool_calls(OutputItems0) ->
  Items = openagentic_openai_responses_utils:ensure_list(OutputItems0),
  lists:foldl(
    fun (Item0, Acc) ->
      Item = openagentic_openai_responses_utils:ensure_map(Item0),
      case openagentic_openai_responses_utils:to_bin(maps:get(<<"type">>, Item, maps:get(type, Item, <<>>))) of
        <<"function_call">> ->
          %% Be tolerant to gateway variants:
          %% - call id: call_id | id | tool_call_id
          %% - name/args: top-level (Responses) or nested under "function" (ChatCompletions-like)
          CallId0 =
            openagentic_openai_responses_request:pick_first(Item, [
              <<"call_id">>,
              call_id,
              <<"id">>,
              id,
              <<"tool_call_id">>,
              tool_call_id,
              <<"toolCallId">>,
              toolCallId
            ]),
          CallId1 = string:trim(openagentic_openai_responses_utils:to_bin(CallId0)),
          CallId = case CallId1 of <<"undefined">> -> <<>>; _ -> CallId1 end,
          Func = openagentic_openai_responses_utils:ensure_map(maps:get(<<"function">>, Item, maps:get(function, Item, #{}))),
          Name0 =
            openagentic_openai_responses_request:pick_first(Item, [<<"name">>, name, <<"tool_name">>, tool_name, <<"toolName">>, toolName]),
          Name = string:trim(openagentic_openai_responses_utils:to_bin(Name0)),
          Name2 =
            case Name of
              <<>> -> openagentic_openai_responses_utils:to_bin(openagentic_openai_responses_request:pick_first(Func, [<<"name">>, name]));
              <<"undefined">> -> openagentic_openai_responses_utils:to_bin(openagentic_openai_responses_request:pick_first(Func, [<<"name">>, name]));
              _ -> Name
            end,
          ArgsEl0 = openagentic_openai_responses_request:pick_first(Item, [<<"arguments">>, arguments]),
          ArgsEl =
            case ArgsEl0 of
              undefined -> maps:get(<<"arguments">>, Func, maps:get(arguments, Func, #{}));
              V -> V
            end,
          Args =
            case ArgsEl of
              M when is_map(M) -> M;
              B when is_binary(B) -> parse_args(B);
              L when is_list(L) -> parse_args(iolist_to_binary(L));
              _ -> #{<<"_raw">> => openagentic_openai_responses_utils:to_bin(ArgsEl)}
            end,
          case {string:trim(CallId), string:trim(Name2)} of
            {<<>>, _} -> Acc;
            {_, <<>>} -> Acc;
            _ -> Acc ++ [#{tool_use_id => CallId, name => Name2, arguments => openagentic_openai_responses_utils:ensure_map(Args)}]
          end;
        _ ->
          Acc
      end
    end,
    [],
    Items
  ).

parse_args(Bin0) ->
  Bin = string:trim(openagentic_openai_responses_utils:to_bin(Bin0)),
  case Bin of
    <<>> -> #{};
    _ ->
      try
        openagentic_json:decode(Bin)
      catch
        _:_ -> #{<<"_raw">> => Bin}
      end
  end.

parse_assistant_text_for_test(OutputItems) ->
  parse_assistant_text(OutputItems).

parse_tool_calls_for_test(OutputItems) ->
  parse_tool_calls(OutputItems).
