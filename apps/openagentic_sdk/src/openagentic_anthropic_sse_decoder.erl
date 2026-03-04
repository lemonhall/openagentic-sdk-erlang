-module(openagentic_anthropic_sse_decoder).

-export([new/0, on_sse_event/2, finish/1]).

%% State:
%% - message_id: binary() | undefined
%% - usage: map() | undefined
%% - failed: binary() | undefined
%% - done: boolean()
%% - blocks: list() where index is position
%%   - {text, [binary()]} (chunks)
%%   - {tool_use, Id, Name, [binary()]} (partial_json chunks)

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

on_sse_event(Ev0, State0) ->
  State = ensure_map(State0),
  Failed = maps:get(failed, State, undefined),
  Done = maps:get(done, State, false),
  case {Failed, Done} of
    {undefined, false} ->
      Ev = ensure_map(Ev0),
      EventType = bin_trim(maps:get(event, Ev, <<>>)),
      DataBin0 = maps:get(data, Ev, <<>>),
      DataBin = bin_trim(DataBin0),
      case DataBin of
        <<>> ->
          {State, []};
        _ ->
          Obj = decode_json_or_undefined(DataBin),
          handle_event(EventType, Obj, State)
      end;
    _ ->
      {State, []}
  end.

finish(State0) ->
  State = ensure_map(State0),
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

handle_event(<<"message_start">>, Obj, State0) ->
  Msg = ensure_map(maps:get(<<"message">>, Obj, maps:get(message, Obj, #{}))),
  MsgId = bin_trim(maps:get(<<"id">>, Msg, maps:get(id, Msg, <<>>))),
  Usage = maps:get(<<"usage">>, Msg, maps:get(usage, Msg, undefined)),
  State1 =
    State0#{
      message_id := case MsgId of <<>> -> maps:get(message_id, State0, undefined); _ -> MsgId end,
      usage := ensure_usage(Usage)
    },
  {State1, []};
handle_event(<<"content_block_start">>, Obj, State0) ->
  Index = pick_int(Obj, [<<"index">>, index], length(maps:get(blocks, State0, []))),
  BlockObj = ensure_map(pick_first(Obj, [<<"content_block">>, content_block, <<"contentBlock">>, contentBlock])),
  Type = bin_trim(pick_first(BlockObj, [<<"type">>, type])),
  State1 = State0#{current_index := Index},
  case Type of
    <<"text">> ->
      {ensure_block_at(Index, {text, []}, State1), []};
    <<"tool_use">> ->
      Id = bin_trim(pick_first(BlockObj, [<<"id">>, id])),
      Name = bin_trim(pick_first(BlockObj, [<<"name">>, name])),
      {ensure_block_at(Index, {tool_use, Id, Name, []}, State1), []};
    _ ->
      {State1, []}
  end;
handle_event(<<"content_block_delta">>, Obj, State0) ->
  Index = pick_int(Obj, [<<"index">>, index], maps:get(current_index, State0, -1)),
  Delta = ensure_map(pick_first(Obj, [<<"delta">>, delta])),
  DeltaType = bin_trim(pick_first(Delta, [<<"type">>, type])),
  case DeltaType of
    <<"text_delta">> ->
      Text = bin_trim(pick_first(Delta, [<<"text">>, text])),
      State1 = append_text_delta(Index, Text, State0),
      case byte_size(Text) > 0 of
        true -> {State1, [Text]};
        false -> {State1, []}
      end;
    <<"input_json_delta">> ->
      Part = bin_trim(pick_first(Delta, [<<"partial_json">>, partial_json, <<"partialJson">>, partialJson])),
      State1 = append_input_json_delta(Index, Part, State0),
      {State1, []};
    _ ->
      {State0, []}
  end;
handle_event(<<"message_delta">>, Obj, State0) ->
  Delta = ensure_map(pick_first(Obj, [<<"delta">>, delta])),
  Stop = bin_trim(pick_first(Delta, [<<"stop_reason">>, stop_reason, <<"stopReason">>, stopReason])),
  Usage0 = pick_first(Obj, [<<"usage">>, usage]),
  Usage = ensure_usage(Usage0),
  State1 =
    State0#{
      stop_reason := case Stop of <<>> -> maps:get(stop_reason, State0, undefined); _ -> Stop end,
      usage := case Usage of undefined -> maps:get(usage, State0, undefined); _ -> Usage end
    },
  {State1, []};
handle_event(<<"message_stop">>, _Obj, State0) ->
  {State0#{done := true}, []};
handle_event(<<"error">>, Obj, State0) ->
  Err = ensure_map(pick_first(Obj, [<<"error">>, error])),
  Msg0 = bin_trim(pick_first(Err, [<<"message">>, message])),
  Msg = case Msg0 of <<>> -> bin_trim(to_bin(Obj)); _ -> Msg0 end,
  {State0#{failed := Msg, done := true}, []};
handle_event(_Other, _Obj, State0) ->
  {State0, []}.

append_text_delta(Index, Text, State0) ->
  Blocks0 = maps:get(blocks, State0, []),
  Blocks = ensure_len(Index, Blocks0),
  Block = lists:nth(Index + 1, Blocks),
  Blocks2 =
    case Block of
      {text, Chunks0} ->
        set_nth(Index + 1, {text, Chunks0 ++ [Text]}, Blocks);
      _ ->
        set_nth(Index + 1, {text, [Text]}, Blocks)
    end,
  State0#{blocks := Blocks2}.

append_input_json_delta(Index, Part, State0) ->
  Blocks0 = maps:get(blocks, State0, []),
  Blocks = ensure_len(Index, Blocks0),
  Block = lists:nth(Index + 1, Blocks),
  Blocks2 =
    case Block of
      {tool_use, Id, Name, Chunks0} ->
        set_nth(Index + 1, {tool_use, Id, Name, Chunks0 ++ [Part]}, Blocks);
      _ ->
        set_nth(Index + 1, {tool_use, <<>>, <<>>, [Part]}, Blocks)
    end,
  State0#{blocks := Blocks2}.

ensure_block_at(Index, NewBlock, State0) ->
  Blocks0 = maps:get(blocks, State0, []),
  Blocks1 = ensure_len(Index, Blocks0),
  Blocks2 = set_nth(Index + 1, NewBlock, Blocks1),
  State0#{blocks := Blocks2}.

ensure_len(Index, Blocks0) ->
  Need = Index + 1,
  Len = length(Blocks0),
  case Len >= Need of
    true -> Blocks0;
    false ->
      Blocks0 ++ lists:duplicate(Need - Len, {text, []})
  end.

set_nth(1, V, [_ | T]) -> [V | T];
set_nth(N, V, [H | T]) when N > 1 ->
  [H | set_nth(N - 1, V, T)];
set_nth(_N, V, []) ->
  [V].

blocks_to_content(Blocks) ->
  lists:map(
    fun (B) ->
      case B of
        {text, Chunks} ->
          #{<<"type">> => <<"text">>, <<"text">> => iolist_to_binary(Chunks)};
        {tool_use, Id, Name, JsonChunks} ->
          JsonBin = iolist_to_binary(JsonChunks),
          Input =
            case decode_json_or_undefined(JsonBin) of
              M when is_map(M) -> M;
              _ -> #{}
            end,
          #{<<"type">> => <<"tool_use">>, <<"id">> => Id, <<"name">> => Name, <<"input">> => Input};
        _ ->
          #{}
      end
    end,
    Blocks
  ).

decode_json_or_undefined(Bin) when is_binary(Bin) ->
  try
    openagentic_json:decode(Bin)
  catch
    _:_ -> undefined
  end;
decode_json_or_undefined(_) ->
  undefined.

ensure_usage(Usage0) ->
  case Usage0 of
    M when is_map(M) -> M;
    _ -> undefined
  end.

pick_first(_Map, []) ->
  undefined;
pick_first(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_first(Map, Rest);
    V -> V
  end.

pick_int(Map, Keys, Default) ->
  V0 = pick_first(Map, Keys),
  case V0 of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(bin_trim(B))) of
        I2 when is_integer(I2) -> I2;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bin_trim(B) ->
  string:trim(to_bin(B)).

