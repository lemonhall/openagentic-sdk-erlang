-module(openagentic_anthropic_sse_decoder_state).

-export([
  new/0,
  finish/1,
  append_text_delta/3,
  append_input_json_delta/3,
  ensure_block_at/3,
  decode_json_or_undefined/1,
  ensure_usage/1
]).

new() ->
  #{
    message_id => undefined,
    usage => undefined,
    stop_reason => undefined,
    failed => undefined,
    done => false,
    current_index => -1,
    blocks => []
  }.

finish(State0) ->
  State = openagentic_anthropic_sse_decoder_utils:ensure_map(State0),
  case maps:get(failed, State, undefined) of
    undefined ->
      MsgId = maps:get(message_id, State, undefined),
      Usage = maps:get(usage, State, undefined),
      Blocks = maps:get(blocks, State, []),
      Content = blocks_to_content(Blocks),
      ModelOut = openagentic_anthropic_parsing:anthropic_content_to_model_output(Content, Usage, MsgId),
      {ok, ModelOut};
    Msg ->
      {error, {provider_error, Msg}}
  end.

append_text_delta(Index, Text, State0) ->
  Blocks = ensure_len(Index, maps:get(blocks, State0, [])),
  Block = lists:nth(Index + 1, Blocks),
  Blocks2 =
    case Block of
      {text, Chunks0} -> set_nth(Index + 1, {text, Chunks0 ++ [Text]}, Blocks);
      _ -> set_nth(Index + 1, {text, [Text]}, Blocks)
    end,
  State0#{blocks := Blocks2}.

append_input_json_delta(Index, Part, State0) ->
  Blocks = ensure_len(Index, maps:get(blocks, State0, [])),
  Block = lists:nth(Index + 1, Blocks),
  Blocks2 =
    case Block of
      {tool_use, Id, Name, Chunks0} -> set_nth(Index + 1, {tool_use, Id, Name, Chunks0 ++ [Part]}, Blocks);
      _ -> set_nth(Index + 1, {tool_use, <<>>, <<>>, [Part]}, Blocks)
    end,
  State0#{blocks := Blocks2}.

ensure_block_at(Index, NewBlock, State0) ->
  Blocks1 = ensure_len(Index, maps:get(blocks, State0, [])),
  Blocks2 = set_nth(Index + 1, NewBlock, Blocks1),
  State0#{blocks := Blocks2}.

blocks_to_content(Blocks) ->
  lists:map(
    fun (B) ->
      case B of
        {text, Chunks} ->
          #{<<"type">> => <<"text">>, <<"text">> => iolist_to_binary(Chunks)};
        {tool_use, Id, Name, JsonChunks} ->
          JsonBin = iolist_to_binary(JsonChunks),
          Input = case decode_json_or_undefined(JsonBin) of M when is_map(M) -> M; _ -> #{} end,
          #{<<"type">> => <<"tool_use">>, <<"id">> => Id, <<"name">> => Name, <<"input">> => Input};
        _ ->
          #{}
      end
    end,
    Blocks
  ).

decode_json_or_undefined(Bin) when is_binary(Bin) ->
  try openagentic_json:decode(Bin) catch _:_ -> undefined end;
decode_json_or_undefined(_) ->
  undefined.

ensure_usage(Usage0) ->
  case Usage0 of M when is_map(M) -> M; _ -> undefined end.

ensure_len(Index, Blocks0) ->
  Need = Index + 1,
  Len = length(Blocks0),
  case Len >= Need of
    true -> Blocks0;
    false -> Blocks0 ++ lists:duplicate(Need - Len, {text, []})
  end.

set_nth(1, V, [_ | T]) -> [V | T];
set_nth(N, V, [H | T]) when N > 1 -> [H | set_nth(N - 1, V, T)];
set_nth(_N, V, []) -> [V].
