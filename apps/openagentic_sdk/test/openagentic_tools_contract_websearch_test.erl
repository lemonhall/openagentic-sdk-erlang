-module(openagentic_tools_contract_websearch_test).

-include_lib("eunit/include/eunit.hrl").

websearch_requires_query_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'query' must be a non-empty string">>}} =
    openagentic_tool_websearch:run(#{query => <<"">>}, #{}).

websearch_ddg_http_error_throws_runtime_exception_test() ->
  Old = os:getenv("TAVILY_API_KEY"),
  _ = os:putenv("TAVILY_API_KEY", ""),
  Transport =
    fun
      (get, _Url, _Headers, _Body) ->
        {ok, {500, [], <<"oops">>}};
      (_Method, _Url, _Headers, _Body) ->
        {error, unexpected}
    end,
  Res = openagentic_tool_websearch:run(#{query => <<"x">>, max_results => 1}, #{websearch_transport => Transport}),
  openagentic_tools_contract_test_support:restore_env("TAVILY_API_KEY", Old),
  ?assertMatch({error, {kotlin_error, <<"RuntimeException">>, _}}, Res),
  {error, {kotlin_error, <<"RuntimeException">>, Msg}} = Res,
  ?assert(binary:match(Msg, <<"HTTP 500 from https://html.duckduckgo.com/html/?q=">>) =/= nomatch),
  ?assert(binary:match(Msg, <<": oops">>) =/= nomatch).

websearch_tavily_error_falls_back_to_ddg_test() ->
  Old = os:getenv("TAVILY_API_KEY"),
  _ = os:putenv("TAVILY_API_KEY", "k"),
  Html = <<"<a class=\"result__a\" href=\"https://example.com\">Example</a>">>,
  Transport =
    fun
      (post, _Url, _Headers, _Body) ->
        {ok, {500, [], <<"tavily down">>}};
      (get, _Url, _Headers, _Body) ->
        {ok, {200, [], Html}};
      (_Method, _Url, _Headers, _Body) ->
        {error, unexpected}
    end,
  {ok, Out} = openagentic_tool_websearch:run(#{query => <<"x">>, max_results => 1}, #{websearch_transport => Transport}),
  openagentic_tools_contract_test_support:restore_env("TAVILY_API_KEY", Old),
  ?assert(maps:is_key(meta, Out)),
  Results = maps:get(results, Out),
  ?assertEqual(1, length(Results)).
