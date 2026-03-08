-module(openagentic_openai_chat_completions).

-behaviour(openagentic_provider).

-export([complete/1]).

-ifdef(TEST).
-export([
  responses_input_to_chat_messages_for_test/1,
  responses_tools_to_chat_tools_for_test/1,
  parse_chat_response_for_test/1
]).
-endif.

complete(Req0) -> openagentic_openai_chat_completions_api:complete(Req0).

-ifdef(TEST).
responses_input_to_chat_messages_for_test(Input) -> openagentic_openai_chat_completions_transform:responses_input_to_chat_messages(Input).
responses_tools_to_chat_tools_for_test(Tools) -> openagentic_openai_chat_completions_transform:responses_tools_to_chat_tools(Tools).
parse_chat_response_for_test(Body) -> openagentic_openai_chat_completions_parse:parse_chat_response(Body).
-endif.
