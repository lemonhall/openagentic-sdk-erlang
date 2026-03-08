-module(openagentic_openai_chat_completions_parse).

-export([parse_chat_response/1]).

parse_chat_response(RespBody0) ->
  RespBody = openagentic_openai_chat_completions_utils:to_bin(RespBody0),
  try
    Root = openagentic_json:decode(RespBody),
    parse_chat_response_obj(Root)
  catch
    _:_ ->
      {error, {invalid_json_response, head_tail_preview(RespBody, 2000)}}
  end.

parse_chat_response_obj(Root0) ->
  Root = openagentic_openai_chat_completions_utils:ensure_map(Root0),
  ResponseId = openagentic_openai_chat_completions_utils:to_bin(maps:get(<<"id">>, Root, maps:get(id, Root, undefined))),
  Usage = openagentic_openai_chat_completions_utils:ensure_map(maps:get(<<"usage">>, Root, maps:get(usage, Root, #{}))),
  Choices0 = openagentic_openai_chat_completions_utils:ensure_list(maps:get(<<"choices">>, Root, maps:get(choices, Root, []))),
  FirstChoice = case Choices0 of [Choice | _] -> openagentic_openai_chat_completions_utils:ensure_map(Choice); _ -> #{} end,
  Message0 = openagentic_openai_chat_completions_utils:ensure_map(maps:get(<<"message">>, FirstChoice, maps:get(message, FirstChoice, #{}))),
  AssistantText = openagentic_openai_chat_completions_utils:to_bin(maps:get(<<"content">>, Message0, maps:get(content, Message0, <<>>))),
  ToolCalls0 = openagentic_openai_chat_completions_utils:ensure_list(maps:get(<<"tool_calls">>, Message0, maps:get(tool_calls, Message0, []))),
  ToolCalls = parse_tool_calls(ToolCalls0),
  {ok, #{assistant_text => AssistantText, tool_calls => ToolCalls, response_id => ResponseId, usage => Usage}}.

parse_tool_calls(ToolCalls0) ->
  ToolCalls = openagentic_openai_chat_completions_utils:ensure_list(ToolCalls0),
  lists:filtermap(
    fun (Tc0) ->
      Tc = openagentic_openai_chat_completions_utils:ensure_map(Tc0),
      Id = openagentic_openai_chat_completions_utils:to_bin(maps:get(<<"id">>, Tc, maps:get(id, Tc, <<>>))),
      Fn0 = openagentic_openai_chat_completions_utils:ensure_map(maps:get(<<"function">>, Tc, maps:get(function, Tc, #{}))),
      Name = openagentic_openai_chat_completions_utils:to_bin(maps:get(<<"name">>, Fn0, maps:get(name, Fn0, <<>>))),
      ArgsStr = openagentic_openai_chat_completions_utils:to_bin(maps:get(<<"arguments">>, Fn0, maps:get(arguments, Fn0, <<>>))),
      Args = parse_args(ArgsStr),
      case {byte_size(string:trim(Id)) > 0, byte_size(string:trim(Name)) > 0} of
        {true, true} -> {true, #{tool_use_id => Id, name => Name, arguments => Args}};
        _ -> false
      end
    end,
    ToolCalls
  ).

parse_args(Bin0) ->
  Bin = string:trim(openagentic_openai_chat_completions_utils:to_bin(Bin0)),
  case byte_size(Bin) of
    0 -> #{};
    _ ->
      try
        Obj = openagentic_json:decode(Bin),
        openagentic_openai_chat_completions_utils:ensure_map(Obj)
      catch
        _:_ -> #{}
      end
  end.

head_tail_preview(Bin0, MaxChars0) ->
  Bin = openagentic_openai_chat_completions_utils:to_bin(Bin0),
  MaxChars = erlang:max(0, MaxChars0),
  case MaxChars =< 0 of
    true -> <<>>;
    false ->
      L = openagentic_openai_chat_completions_utils:bin_to_list_safe(Bin),
      case length(L) =< MaxChars of
        true -> unicode:characters_to_binary(L, utf8);
        false ->
          HeadLen = MaxChars div 2,
          TailLen = MaxChars - HeadLen,
          Head = lists:sublist(L, HeadLen),
          Tail = lists:nthtail(length(L) - TailLen, L),
          unicode:characters_to_binary(Head ++ "
…truncated…
" ++ Tail, utf8)
      end
  end.
