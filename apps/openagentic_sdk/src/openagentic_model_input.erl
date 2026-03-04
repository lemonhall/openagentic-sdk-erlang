-module(openagentic_model_input).

-export([build_responses_input/1, encode_tool_output_for_model/1]).

build_responses_input(Events) when is_list(Events) ->
  build_responses_input(Events, #{seen_call_ids => #{}}).

build_responses_input([], _State) ->
  [];
build_responses_input([E | Rest], State0) when is_map(E) ->
  Type = maps:get(type, E, <<>>),
  {Items, State1} =
    case Type of
      <<"user.message">> ->
        {[
          #{role => <<"user">>, content => maps:get(text, E, <<>>)}
        ], State0};
      <<"assistant.message">> ->
        {[
          #{role => <<"assistant">>, content => maps:get(text, E, <<>>)}
        ], State0};
      <<"tool.use">> ->
        ToolUseId = maps:get(tool_use_id, E, <<>>),
        Name = maps:get(name, E, <<>>),
        Args = maps:get(input, E, #{}),
        ArgsStr = openagentic_json:encode(Args),
        Seen0 = maps:get(seen_call_ids, State0, #{}),
        Seen1 = Seen0#{ToolUseId => true},
        Item = #{
          type => <<"function_call">>,
          call_id => ToolUseId,
          name => Name,
          arguments => ArgsStr
        },
        {[Item], State0#{seen_call_ids => Seen1}};
      <<"tool.result">> ->
        ToolUseId = maps:get(tool_use_id, E, <<>>),
        Seen = maps:get(seen_call_ids, State0, #{}),
        case maps:get(ToolUseId, Seen, false) of
          true ->
            Output = maps:get(output, E, null),
            OutStr = encode_tool_output_for_model(Output),
            Item = #{
              type => <<"function_call_output">>,
              call_id => ToolUseId,
              output => OutStr
            },
            {[Item], State0};
          false ->
            {[], State0}
        end;
      _ ->
        {[], State0}
    end,
  Items ++ build_responses_input(Rest, State1).

encode_tool_output_for_model(null) ->
  <<"null">>;
encode_tool_output_for_model(undefined) ->
  <<"null">>;
encode_tool_output_for_model(Out) ->
  %% For now keep it simple: JSON encode as string (Kotlin does truncation + placeholders).
  openagentic_json:encode(Out).

