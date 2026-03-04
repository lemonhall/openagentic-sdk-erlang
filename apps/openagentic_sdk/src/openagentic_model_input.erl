-module(openagentic_model_input).

-export([build_responses_input/1, encode_tool_output_for_model/1]).

build_responses_input(Events) when is_list(Events) ->
  Compacted = compacted_tool_ids(Events),
  build_responses_input(Events, #{seen_call_ids => #{}, compacted_ids => Compacted}).

build_responses_input([], _State) ->
  [];
build_responses_input([E | Rest], State0) when is_map(E) ->
  Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
  {Items, State1} =
    case Type of
      <<"user.message">> ->
        {[
          #{role => <<"user">>, content => to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>)))}
        ], State0};
      <<"user.compaction">> ->
        {[
          #{role => <<"user">>, content => <<"What did we do so far?">>}
        ], State0};
      <<"assistant.message">> ->
        {[
          #{role => <<"assistant">>, content => to_bin(maps:get(text, E, maps:get(<<"text">>, E, <<>>)))}
        ], State0};
      <<"tool.use">> ->
        ToolUseId = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
        Name = to_bin(maps:get(name, E, maps:get(<<"name">>, E, <<>>))),
        Args = ensure_map(maps:get(input, E, maps:get(<<"input">>, E, #{}))),
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
        ToolUseId = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
        Seen = maps:get(seen_call_ids, State0, #{}),
        case maps:get(ToolUseId, Seen, false) of
          true ->
            Output0 = maps:get(output, E, maps:get(<<"output">>, E, null)),
            Output =
              case is_compacted(ToolUseId, State0) of
                true -> <<"[Old tool result content cleared]">>;
                false -> Output0
              end,
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

%% internal
compacted_tool_ids(Events0) ->
  Events = ensure_list(Events0),
  lists:foldl(
    fun (E0, Acc0) ->
      E = ensure_map(E0),
      Type = to_bin(maps:get(type, E, maps:get(<<"type">>, E, <<>>))),
      case Type of
        <<"tool.output_compacted">> ->
          Tid = to_bin(maps:get(tool_use_id, E, maps:get(<<"tool_use_id">>, E, <<>>))),
          case byte_size(string:trim(Tid)) > 0 of true -> Acc0#{Tid => true}; false -> Acc0 end;
        _ ->
          Acc0
      end
    end,
    #{},
    Events
  ).

is_compacted(ToolUseId, State0) ->
  C = maps:get(compacted_ids, State0, #{}),
  maps:get(ToolUseId, C, false) =:= true.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
