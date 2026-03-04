-module(openagentic_anthropic_parsing).

-export([
  responses_input_to_messages/1,
  responses_tools_to_anthropic_tools/1,
  anthropic_content_to_model_output/3
]).

%% ---- input (Responses format) -> Anthropic Messages API ----
%%
%% Input item formats (from SDK core loop):
%% - #{role => <<"system">>, content => <<"...">>}
%% - #{role => <<"user">>, content => <<"...">>}
%% - #{role => <<"assistant">>, content => <<"...">>}
%% - #{type => <<"function_call">>, call_id => <<"...">>, name => <<"...">>, arguments => <<"...json...">>}
%% - #{type => <<"function_call_output">>, call_id => <<"...">>, output => <<"...">>}
%%
%% Returns {SystemPromptOrUndefined, MessagesList}.
responses_input_to_messages(Input0) ->
  Input = ensure_list(Input0),
  responses_input_loop(Input, #{system_parts => [], messages => [], pending_role => <<>>, pending_blocks => []}).

responses_input_loop([], Acc0) ->
  Acc1 = flush_pending(Acc0),
  System = join_system(maps:get(system_parts, Acc1, [])),
  Messages0 = maps:get(messages, Acc1, []),
  Messages = ensure_first_user(Messages0),
  {System, Messages};
responses_input_loop([Item0 | Rest], Acc0) ->
  Item = ensure_map(Item0),
  Role = bin_trim(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Type = bin_trim(maps:get(type, Item, maps:get(<<"type">>, Item, <<>>))),
  Acc1 =
    case {Role, Type} of
      {<<"system">>, _} ->
        AccS = flush_pending(Acc0),
        Content = bin_trim(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
        case byte_size(Content) > 0 of
          true ->
            Sys0 = maps:get(system_parts, AccS, []),
            AccS#{system_parts := Sys0 ++ [Content]};
          false ->
            AccS
        end;
      {_, <<"function_call">>} ->
        CallId = bin_trim(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, maps:get(callId, Item, maps:get(<<"callId">>, Item, <<>>))))),
        Name = bin_trim(maps:get(name, Item, maps:get(<<"name">>, Item, <<>>))),
        ArgsRaw = bin_trim(maps:get(arguments, Item, maps:get(<<"arguments">>, Item, <<>>))),
        ArgsObj = parse_args_to_map(ArgsRaw),
        Block = #{<<"type">> => <<"tool_use">>, <<"id">> => CallId, <<"name">> => Name, <<"input">> => ArgsObj},
        append_block(<<"assistant">>, Block, Acc0);
      {_, <<"function_call_output">>} ->
        CallId = bin_trim(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, maps:get(callId, Item, maps:get(<<"callId">>, Item, <<>>))))),
        Output = bin_trim(maps:get(output, Item, maps:get(<<"output">>, Item, <<>>))),
        Block = #{<<"type">> => <<"tool_result">>, <<"tool_use_id">> => CallId, <<"content">> => Output},
        append_block(<<"user">>, Block, Acc0);
      {<<"user">>, _} ->
        Content = bin_trim(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
        Block = #{<<"type">> => <<"text">>, <<"text">> => Content},
        append_block(<<"user">>, Block, Acc0);
      {<<"assistant">>, _} ->
        Content = bin_trim(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
        Block = #{<<"type">> => <<"text">>, <<"text">> => Content},
        append_block(<<"assistant">>, Block, Acc0);
      _ ->
        Acc0
    end,
  responses_input_loop(Rest, Acc1).

flush_pending(Acc0) ->
  Blocks = maps:get(pending_blocks, Acc0, []),
  Role = maps:get(pending_role, Acc0, <<>>),
  case Blocks of
    [] ->
      Acc0;
    _ ->
      Msg =
        case Blocks of
          [One] ->
            case maps:get(<<"type">>, One, <<>>) of
              <<"text">> -> #{<<"role">> => Role, <<"content">> => maps:get(<<"text">>, One, <<>>)};
              _ -> #{<<"role">> => Role, <<"content">> => Blocks}
            end;
          _ ->
            #{<<"role">> => Role, <<"content">> => Blocks}
        end,
      Msgs0 = maps:get(messages, Acc0, []),
      Acc0#{messages := Msgs0 ++ [Msg], pending_role := <<>>, pending_blocks := []}
  end.

append_block(Role, Block, Acc0) ->
  PendingRole = maps:get(pending_role, Acc0, <<>>),
  Acc1 =
    case PendingRole =:= Role of
      true -> Acc0;
      false -> flush_pending(Acc0)
    end,
  Blocks0 = maps:get(pending_blocks, Acc1, []),
  Acc1#{pending_role := Role, pending_blocks := Blocks0 ++ [Block]}.

ensure_first_user([]) ->
  [];
ensure_first_user([First | Rest]) ->
  Role = bin_trim(maps:get(<<"role">>, ensure_map(First), <<>>)),
  case Role of
    <<"assistant">> ->
      [#{<<"role">> => <<"user">>, <<"content">> => <<"(continue)">>} , First | Rest];
    _ ->
      [First | Rest]
  end.

join_system([]) ->
  undefined;
join_system(Parts) ->
  Bin = iolist_to_binary(lists:join(<<"\n\n">>, Parts)),
  case byte_size(bin_trim(Bin)) > 0 of
    true -> bin_trim(Bin);
    false -> undefined
  end.

parse_args_to_map(ArgsRaw0) ->
  ArgsRaw = bin_trim(ArgsRaw0),
  case byte_size(ArgsRaw) of
    0 ->
      #{};
    _ ->
      try
        Obj = openagentic_json:decode(ArgsRaw),
        ensure_map(Obj)
      catch
        _:_ -> #{}
      end
  end.

%% ---- tools (Responses schema) -> Anthropic tool schema ----
responses_tools_to_anthropic_tools(Tools0) ->
  Tools = ensure_list(Tools0),
  lists:filtermap(
    fun (T0) ->
      T = ensure_map(T0),
      Name = bin_trim(pick_first(T, [<<"name">>, name])),
      case byte_size(Name) > 0 of
        false ->
          false;
        true ->
          Desc = bin_trim(pick_first(T, [<<"description">>, description])),
          Params0 = pick_first(T, [<<"parameters">>, parameters]),
          Params =
            case Params0 of
              M when is_map(M) -> M;
              _ -> #{<<"type">> => <<"object">>, <<"properties">> => #{}}
            end,
          Tool0 = #{<<"name">> => Name, <<"input_schema">> => Params},
          Tool =
            case byte_size(Desc) > 0 of
              true -> Tool0#{<<"description">> => Desc};
              false -> Tool0
            end,
          {true, Tool}
      end
    end,
    Tools
  ).

%% ---- Anthropic response content blocks -> ModelOutput ----
anthropic_content_to_model_output(Content0, Usage0, MessageId0) ->
  Content = ensure_list(Content0),
  Usage = case Usage0 of M when is_map(M) -> M; _ -> undefined end,
  MessageId = case MessageId0 of undefined -> undefined; V -> bin_trim(to_bin(V)) end,
  {TextParts, ToolCalls} =
    lists:foldl(
      fun (Block0, {TxtAcc0, CallsAcc0}) ->
        Block = ensure_map(Block0),
        Type = bin_trim(pick_first(Block, [<<"type">>, type])),
        case Type of
          <<"text">> ->
            Txt = bin_trim(pick_first(Block, [<<"text">>, text])),
            case byte_size(Txt) > 0 of
              true -> {TxtAcc0 ++ [Txt], CallsAcc0};
              false -> {TxtAcc0, CallsAcc0}
            end;
          <<"tool_use">> ->
            Id = bin_trim(pick_first(Block, [<<"id">>, id])),
            Name = bin_trim(pick_first(Block, [<<"name">>, name])),
            Input = ensure_map(pick_first(Block, [<<"input">>, input])),
            Call = #{tool_use_id => Id, name => Name, arguments => Input},
            {TxtAcc0, CallsAcc0 ++ [Call]};
          _ ->
            {TxtAcc0, CallsAcc0}
        end
      end,
      {[], []},
      Content
    ),
  AssistantText = iolist_to_binary(TextParts),
  #{
    assistant_text => AssistantText,
    tool_calls => ToolCalls,
    response_id => MessageId,
    usage => Usage
  }.

pick_first(_Map, []) ->
  undefined;
pick_first(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> pick_first(Map, Rest);
    V -> V
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bin_trim(B) ->
  string:trim(to_bin(B)).

