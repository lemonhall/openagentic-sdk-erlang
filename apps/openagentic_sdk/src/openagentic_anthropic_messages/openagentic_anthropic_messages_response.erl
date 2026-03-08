-module(openagentic_anthropic_messages_response).

-export([parse_message_response/1]).

parse_message_response(Body) ->
  try
    Root = openagentic_anthropic_messages_utils:ensure_map(openagentic_json:decode(Body)),
    MsgId = maps:get(<<"id">>, Root, undefined),
    Usage = maps:get(<<"usage">>, Root, undefined),
    Content = openagentic_anthropic_messages_utils:ensure_list(maps:get(<<"content">>, Root, [])),
    {ok, openagentic_anthropic_parsing:anthropic_content_to_model_output(Content, openagentic_anthropic_messages_utils:ensure_map(Usage), MsgId)}
  catch
    _:_ ->
      {error, {provider_error, <<"invalid JSON response">>}}
  end.
