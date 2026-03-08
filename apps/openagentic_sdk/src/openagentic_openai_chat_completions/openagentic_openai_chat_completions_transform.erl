-module(openagentic_openai_chat_completions_transform).

-export([responses_input_to_chat_messages/1, responses_tools_to_chat_tools/1]).

responses_input_to_chat_messages(InputItems0) ->
  InputItems = openagentic_openai_chat_completions_utils:ensure_list(InputItems0),
  responses_input_to_chat_messages_loop(InputItems, [], []).

responses_input_to_chat_messages_loop([], PendingToolCallsRev, AccRev) ->
  lists:reverse(flush_pending(PendingToolCallsRev, AccRev));
responses_input_to_chat_messages_loop([Item0 | Rest], PendingToolCallsRev0, AccRev0) ->
  Item = openagentic_openai_chat_completions_utils:ensure_map(Item0),
  Role = openagentic_openai_chat_completions_utils:to_bin(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Type = openagentic_openai_chat_completions_utils:to_bin(maps:get(type, Item, maps:get(<<"type">>, Item, <<>>))),
  case {Role, Type} of
    {<<>>, <<"function_call">>} ->
      Tc = tool_call_item(Item),
      responses_input_to_chat_messages_loop(Rest, [Tc | PendingToolCallsRev0], AccRev0);
    {<<>>, <<"function_call_output">>} ->
      CallId = openagentic_openai_chat_completions_utils:to_bin(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, <<>>))),
      Out = openagentic_openai_chat_completions_utils:to_bin(maps:get(output, Item, maps:get(<<"output">>, Item, <<>>))),
      AccRev1 = flush_pending(PendingToolCallsRev0, AccRev0),
      ToolMsg = #{<<"role">> => <<"tool">>, <<"tool_call_id">> => CallId, <<"content">> => Out},
      responses_input_to_chat_messages_loop(Rest, [], [ToolMsg | AccRev1]);
    {<<"system">>, _} -> append_role_message(Rest, PendingToolCallsRev0, AccRev0, <<"system">>, Item);
    {<<"assistant">>, _} -> append_role_message(Rest, PendingToolCallsRev0, AccRev0, <<"assistant">>, Item);
    _ -> append_role_message(Rest, PendingToolCallsRev0, AccRev0, <<"user">>, Item)
  end.

tool_call_item(Item) ->
  CallId = openagentic_openai_chat_completions_utils:to_bin(maps:get(call_id, Item, maps:get(<<"call_id">>, Item, <<>>))),
  Name = openagentic_openai_chat_completions_utils:to_bin(maps:get(name, Item, maps:get(<<"name">>, Item, <<>>))),
  Args = openagentic_openai_chat_completions_utils:to_bin(maps:get(arguments, Item, maps:get(<<"arguments">>, Item, <<>>))),
  #{<<"id">> => CallId, <<"type">> => <<"function">>, <<"function">> => #{<<"name">> => Name, <<"arguments">> => Args}}.

append_role_message(Rest, PendingToolCallsRev0, AccRev0, RoleOut, Item) ->
  Content = openagentic_openai_chat_completions_utils:to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
  AccRev1 = flush_pending(PendingToolCallsRev0, AccRev0),
  responses_input_to_chat_messages_loop(Rest, [], [#{<<"role">> => RoleOut, <<"content">> => Content} | AccRev1]).

flush_pending([], AccRev) -> AccRev;
flush_pending(PendingToolCallsRev, AccRev) -> [assistant_tool_calls(lists:reverse(PendingToolCallsRev)) | AccRev].

assistant_tool_calls(ToolCalls) ->
  #{<<"role">> => <<"assistant">>, <<"content">> => <<>>, <<"tool_calls">> => ToolCalls}.

responses_tools_to_chat_tools(Tools0) ->
  Tools = openagentic_openai_chat_completions_utils:ensure_list(Tools0),
  lists:filtermap(
    fun (T0) ->
      T = openagentic_openai_chat_completions_utils:ensure_map(T0),
      Name = openagentic_openai_chat_completions_utils:to_bin(maps:get(name, T, maps:get(<<"name">>, T, <<>>))),
      case byte_size(string:trim(Name)) > 0 of
        false -> false;
        true ->
          Desc = openagentic_openai_chat_completions_utils:to_bin(maps:get(description, T, maps:get(<<"description">>, T, <<>>))),
          Params = openagentic_openai_chat_completions_utils:ensure_map(maps:get(parameters, T, maps:get(<<"parameters">>, T, #{}))),
          Tool = #{<<"type">> => <<"function">>, <<"function">> => #{<<"name">> => Name, <<"description">> => Desc, <<"parameters">> => Params}},
          {true, Tool}
      end
    end,
    Tools
  ).
