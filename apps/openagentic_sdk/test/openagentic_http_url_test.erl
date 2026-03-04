-module(openagentic_http_url_test).

-include_lib("eunit/include/eunit.hrl").

join_trims_trailing_slashes_test() ->
  ?assertEqual(
    "https://example.com/v1/responses",
    openagentic_http_url:join("https://example.com/v1/", "/responses")
  ),
  ?assertEqual(
    "https://example.com/v1/responses",
    openagentic_http_url:join("https://example.com/v1///", "responses")
  ).

join_trims_leading_slashes_test() ->
  ?assertEqual(
    "https://example.com/v1/chat/completions",
    openagentic_http_url:join("https://example.com/v1", "///chat/completions")
  ).

