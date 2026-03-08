-module(openagentic_tool_websearch_tavily).

-export([first_non_blank/1, tavily_endpoint/1, tavily_out/7, tool_dotenv/1]).

tavily_out(Query, MaxResults, Allowed, Blocked, TavilyKey, Endpoint0, Ctx) ->
  Endpoint = openagentic_tool_websearch_utils:to_bin(Endpoint0),
  Payload = #{api_key => TavilyKey, query => Query, max_results => MaxResults},
  Body = openagentic_json:encode(Payload),
  Headers = [{"content-type", "application/json"}],
  case openagentic_tool_websearch_runtime:http_request(post, Endpoint, Headers, Body, Ctx) of
    {ok, {Status, _RespHeaders, RespBody}} when Status >= 200, Status < 300 ->
      Obj0 = openagentic_json:decode(openagentic_tool_websearch_utils:to_bin_safe_utf8(RespBody)),
      Obj = openagentic_tool_websearch_utils:ensure_map(Obj0),
      ResultsIn = maps:get(<<"results">>, Obj, []),
      Results = tavily_results(ResultsIn, Allowed, Blocked, MaxResults),
      {ok, #{query => Query, results => Results, total_results => length(Results)}};
    {ok, {Status, _RespHeaders, RespBody}} ->
      UrlBin = openagentic_tool_websearch_utils:to_bin(Endpoint),
      Raw = openagentic_tool_websearch_utils:to_bin_safe_utf8(RespBody),
      Msg0 = iolist_to_binary([<<"HTTP ">>, integer_to_binary(Status), <<" from ">>, UrlBin, <<": ">>, Raw]),
      {error, openagentic_tool_websearch_utils:trim_bin(Msg0)};
    {error, Err} ->
      {error, Err}
  end.

tool_dotenv(Ctx0) ->
  %% Avoid implicit `.env` reads in unit tests that call tools directly without a project_dir.
  Ctx = openagentic_tool_websearch_utils:ensure_map(Ctx0),
  case maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, undefined)) of
    undefined -> #{};
    null -> #{};
    false -> #{};
    <<>> -> #{};
    "" -> #{};
    ProjectDir0 ->
      ProjectDir = string:trim(openagentic_tool_websearch_utils:to_bin(ProjectDir0)),
      case byte_size(ProjectDir) > 0 of
        false -> #{};
        true -> openagentic_dotenv:load(filename:join([openagentic_tool_websearch_utils:to_list(ProjectDir), ".env"]))
      end
  end.

tavily_endpoint(undefined) -> <<"https://api.tavily.com/search">>;
tavily_endpoint(null) -> <<"https://api.tavily.com/search">>;
tavily_endpoint(false) -> <<"https://api.tavily.com/search">>;
tavily_endpoint(<<>>) -> <<"https://api.tavily.com/search">>;
tavily_endpoint("") -> <<"https://api.tavily.com/search">>;
tavily_endpoint(Url0) ->
  Url1 = string:trim(openagentic_tool_websearch_utils:to_bin(Url0)),
  Url = trim_trailing_slash(Url1),
  case openagentic_tool_websearch_domain:ends_with(Url, <<"/search">>) of
    true -> Url;
    false -> openagentic_http_url:join(Url, <<"search">>)
  end.

trim_trailing_slash(Bin0) ->
  Bin = openagentic_tool_websearch_utils:to_bin(Bin0),
  case byte_size(Bin) of
    0 -> Bin;
    _ ->
      case binary:last(Bin) of
        $/ -> binary:part(Bin, 0, byte_size(Bin) - 1);
        _ -> Bin
      end
  end.

first_non_blank([]) -> undefined;
first_non_blank([false | Rest]) -> first_non_blank(Rest);
first_non_blank([undefined | Rest]) -> first_non_blank(Rest);
first_non_blank([null | Rest]) -> first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V = string:trim(openagentic_tool_websearch_utils:to_bin(V0)),
  case V of
    <<>> -> first_non_blank(Rest);
    <<"undefined">> -> first_non_blank(Rest);
    <<"false">> -> first_non_blank(Rest);
    _ -> V
  end.

tavily_results(ResultsIn, Allowed, Blocked, MaxResults) when is_list(ResultsIn) ->
  Filtered =
    lists:foldl(
      fun (El0, Acc) ->
        case length(Acc) >= MaxResults of
          true -> Acc;
          false ->
            El = openagentic_tool_websearch_utils:ensure_map(El0),
            Url0 = maps:get(<<"url">>, El, undefined),
            Url = string:trim(openagentic_tool_websearch_utils:to_bin(Url0)),
            case byte_size(Url) > 0 of
              false -> Acc;
              true ->
                case openagentic_tool_websearch_domain:domain_allowed(Url, Allowed, Blocked) of
                  false -> Acc;
                  true ->
                    Title = maps:get(<<"title">>, El, null),
                    Content0 = maps:get(<<"content">>, El, maps:get(<<"snippet">>, El, null)),
                    [#{title => Title, url => Url, content => Content0, source => <<"tavily">>} | Acc]
                end
            end
        end
      end,
      [],
      ResultsIn
    ),
  lists:reverse(Filtered);
tavily_results(_Other, _Allowed, _Blocked, _MaxResults) ->
  [].
