-module(openagentic_testing_provider_echo_context).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Input = ensure_list(maps:get(input, Req, [])),
  Echo = extract_system_context(Input),
  {ok, #{assistant_text => Echo, tool_calls => [], response_id => <<"resp_echo_context_1">>, usage => #{}}}.

extract_system_context([]) -> <<>>;
extract_system_context([Item0 | Rest]) ->
  Item = ensure_map(Item0),
  Role = to_bin(maps:get(role, Item, maps:get(<<"role">>, Item, <<>>))),
  Content = to_bin(maps:get(content, Item, maps:get(<<"content">>, Item, <<>>))),
  case {Role, binary:match(Content, <<"TASK_GOVERNANCE_CONTEXT_V1">>)} of
    {<<"system">>, nomatch} -> extract_system_context(Rest);
    {<<"system">>, _} -> Content;
    _ -> extract_system_context(Rest)
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
