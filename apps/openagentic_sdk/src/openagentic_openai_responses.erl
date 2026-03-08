-module(openagentic_openai_responses).

-export([complete/1, query/2]).
-export([parse_assistant_text_for_test/1, parse_tool_calls_for_test/1, request_payload_for_test/5, build_headers_for_test/3]).

complete(Req0) -> openagentic_openai_responses_api:complete(Req0).
query(Prompt0, Opts0) -> openagentic_openai_responses_api:query(Prompt0, Opts0).
parse_assistant_text_for_test(OutputItems) -> openagentic_openai_responses_normalize:parse_assistant_text_for_test(OutputItems).
parse_tool_calls_for_test(OutputItems) -> openagentic_openai_responses_normalize:parse_tool_calls_for_test(OutputItems).
request_payload_for_test(Model, InputItems0, Tools0, Prev, Req0) -> openagentic_openai_responses_request:request_payload_for_test(Model, InputItems0, Tools0, Prev, Req0).
build_headers_for_test(ApiKeyHeader0, ApiKey0, AcceptEventStream) -> openagentic_openai_responses_request:build_headers_for_test(ApiKeyHeader0, ApiKey0, AcceptEventStream).
