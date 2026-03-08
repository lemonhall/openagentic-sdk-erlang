-module(openagentic_anthropic_parsing).

-export([
  responses_input_to_messages/1,
  responses_tools_to_anthropic_tools/1,
  anthropic_content_to_model_output/3
]).

responses_input_to_messages(Input) ->
  openagentic_anthropic_parsing_input:responses_input_to_messages(Input).

responses_tools_to_anthropic_tools(Tools) ->
  openagentic_anthropic_parsing_tools:responses_tools_to_anthropic_tools(Tools).

anthropic_content_to_model_output(Content, Usage, MessageId) ->
  openagentic_anthropic_parsing_output:anthropic_content_to_model_output(Content, Usage, MessageId).
