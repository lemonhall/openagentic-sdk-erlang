-module(openagentic_tool_websearch_api).

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_websearch_utils:ensure_map(Input0),
  Ctx = openagentic_tool_websearch_utils:ensure_map(Ctx0),
  Query0 = maps:get(<<"query">>, Input, maps:get(query, Input, undefined)),
  Query = string:trim(openagentic_tool_websearch_utils:to_bin(Query0)),
  case byte_size(Query) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'query' must be a non-empty string">>}};
    true ->
      MaxResults0 = openagentic_tool_websearch_utils:int_opt(Input, [<<"max_results">>, max_results], 5),
      case is_integer(MaxResults0) andalso MaxResults0 > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'max_results' must be a positive integer">>}};
        true ->
          Allowed = openagentic_tool_websearch_utils:string_list(Input, <<"allowed_domains">>, allowed_domains),
          Blocked = openagentic_tool_websearch_utils:string_list(Input, <<"blocked_domains">>, blocked_domains),
          DotEnv = openagentic_tool_websearch_tavily:tool_dotenv(Ctx),
          TavilyKey = openagentic_tool_websearch_tavily:first_non_blank([
            os:getenv("TAVILY_API_KEY"),
            openagentic_dotenv:get(<<"TAVILY_API_KEY">>, DotEnv)
          ]),
          TavilyUrl = openagentic_tool_websearch_tavily:first_non_blank([
            os:getenv("TAVILY_URL"),
            openagentic_dotenv:get(<<"TAVILY_URL">>, DotEnv)
          ]),
          Endpoint = openagentic_tool_websearch_tavily:tavily_endpoint(TavilyUrl),
          case byte_size(openagentic_tool_websearch_utils:to_bin(TavilyKey)) > 0 of
            false ->
              openagentic_tool_websearch_ddg:ddg_out(Query, MaxResults0, Allowed, Blocked, Ctx);
            true ->
              maybe_fallback_to_ddg(Query, MaxResults0, Allowed, Blocked, TavilyKey, Endpoint, Ctx)
          end
      end
  end.

maybe_fallback_to_ddg(Query, MaxResults0, Allowed, Blocked, TavilyKey, Endpoint, Ctx) ->
  case openagentic_tool_websearch_tavily:tavily_out(Query, MaxResults0, Allowed, Blocked, TavilyKey, Endpoint, Ctx) of
    {ok, Out} -> {ok, Out};
    {error, Err} ->
      case openagentic_tool_websearch_ddg:ddg_out(Query, MaxResults0, Allowed, Blocked, Ctx) of
        {ok, Out2} ->
          Meta = #{
            primary_source => <<"tavily">>,
            fallback_source => <<"duckduckgo">>,
            tavily_url => openagentic_tool_websearch_utils:to_bin(Endpoint),
            tavily_error => openagentic_tool_websearch_utils:to_bin(Err)
          },
          {ok, Out2#{meta => Meta}};
        {error, DdgErr} ->
          {error, DdgErr}
      end
  end.
