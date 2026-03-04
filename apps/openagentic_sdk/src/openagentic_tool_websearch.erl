-module(openagentic_tool_websearch).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"WebSearch">>.

description() ->
  <<"Search the web (Tavily backend; falls back to DuckDuckGo HTML when TAVILY_API_KEY is missing).">>.

run(Input0, _Ctx0) ->
  Input = ensure_map(Input0),
  Query0 = maps:get(<<"query">>, Input, maps:get(query, Input, undefined)),
  Query = string:trim(to_bin(Query0)),
  case byte_size(Query) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'query' must be a non-empty string">>}};
    true ->
      MaxResults0 = int_opt(Input, [<<"max_results">>, max_results], 5),
      case is_integer(MaxResults0) andalso MaxResults0 > 0 of
        false -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'max_results' must be a positive integer">>}};
        true ->
          Allowed = string_list(Input, <<"allowed_domains">>, allowed_domains),
          Blocked = string_list(Input, <<"blocked_domains">>, blocked_domains),
          TavilyKey = string:trim(to_bin(os:getenv("TAVILY_API_KEY"))),
          case byte_size(TavilyKey) > 0 of
            false ->
              ddg_out(Query, MaxResults0, Allowed, Blocked);
            true ->
              case tavily_out(Query, MaxResults0, Allowed, Blocked, TavilyKey) of
                {ok, Out} -> {ok, Out};
                {error, Err} ->
                  {ok, Out2} = ddg_out(Query, MaxResults0, Allowed, Blocked),
                  Meta = #{
                    primary_source => <<"tavily">>,
                    fallback_source => <<"duckduckgo">>,
                    tavily_error => to_bin(Err)
                  },
                  {ok, Out2#{meta => Meta}}
              end
          end
      end
  end.

ddg_out(Query, MaxResults, Allowed, Blocked) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Url = <<"https://html.duckduckgo.com/html/?q=", (urlencode(Query))/binary>>,
  Headers = [{"user-agent", "openagentic-sdk-erlang/0.1"}, {"accept", "text/html,application/xhtml+xml"}],
  Raw =
    case httpc:request(get, {binary_to_list(Url), Headers}, [{timeout, 60000}], [{body_format, binary}], openagentic_websearch) of
      {ok, {{_, 200, _}, _RespHeaders, Body}} -> Body;
      _ -> <<>>
    end,
  Results =
    case byte_size(Raw) > 0 of
      true -> ddg_parse_results(Raw, MaxResults, Allowed, Blocked);
      false -> []
    end,
  {ok, #{
    query => Query,
    results => Results,
    total_results => length(Results)
  }}.

tavily_out(Query, MaxResults, Allowed, Blocked, TavilyKey) ->
  ok = ensure_httpc_started(),
  ok = configure_proxy(),
  Endpoint = "https://api.tavily.com/search",
  Payload = #{
    api_key => TavilyKey,
    query => Query,
    max_results => MaxResults
  },
  Body = openagentic_json:encode(Payload),
  Headers = [{"content-type", "application/json"}],
  case httpc:request(post, {Endpoint, Headers, "application/json", Body}, [{timeout, 60000}], [{body_format, binary}], openagentic_websearch) of
    {ok, {{_, Status, _}, _RespHeaders, RespBody}} when Status >= 200, Status < 300 ->
      Obj0 = openagentic_json:decode(RespBody),
      Obj = ensure_map(Obj0),
      ResultsIn = maps:get(<<"results">>, Obj, []),
      Results = tavily_results(ResultsIn, Allowed, Blocked, MaxResults),
      {ok, #{
        query => Query,
        results => Results,
        total_results => length(Results)
      }};
    {ok, {{_, Status, _}, _RespHeaders, RespBody}} ->
      {error, iolist_to_binary([<<"HTTP ">>, integer_to_binary(Status), <<" from tavily: ">>, RespBody])};
    Err ->
      {error, Err}
  end.

tavily_results(ResultsIn, Allowed, Blocked, MaxResults) when is_list(ResultsIn) ->
  Filtered =
    lists:foldl(
      fun (El0, Acc) ->
        case length(Acc) >= MaxResults of
          true -> Acc;
          false ->
            El = ensure_map(El0),
            Url0 = maps:get(<<"url">>, El, undefined),
            Url = string:trim(to_bin(Url0)),
            case byte_size(Url) > 0 of
              false -> Acc;
              true ->
                case domain_allowed(Url, Allowed, Blocked) of
                  false -> Acc;
                  true ->
                    Title = maps:get(<<"title">>, El, null),
                    Content0 = maps:get(<<"content">>, El, maps:get(<<"snippet">>, El, null)),
                    Obj = #{
                      title => Title,
                      url => Url,
                      content => Content0,
                      source => <<"tavily">>
                    },
                    [Obj | Acc]
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

ddg_parse_results(Html, MaxResults, Allowed, Blocked) ->
  %% Regex: <a ... class="result__a" ... href="X" ...>TITLE</a>
  Pattern = <<"<a[^>]*class=\\\"result__a\\\"[^>]*href=\\\"([^\\\"]+)\\\"[^>]*>(.*?)</a>">>,
  Opts = [global, caseless, {capture, [1, 2], binary}],
  case re:run(Html, Pattern, Opts) of
    nomatch -> [];
    {match, Captures} ->
      lists:reverse(take_ddg(Captures, MaxResults, Allowed, Blocked, []))
  end.

take_ddg([], _Max, _Allowed, _Blocked, Acc) -> Acc;
take_ddg(_Caps, Max, _Allowed, _Blocked, Acc) when length(Acc) >= Max -> Acc;
take_ddg([[Href0, TitleHtml0] | Rest], Max, Allowed, Blocked, Acc) ->
  Href = html_unescape(Href0),
  Url = decode_ddg_redirect(Href),
  case {byte_size(string:trim(Url)), domain_allowed(Url, Allowed, Blocked)} of
    {0, _} ->
      take_ddg(Rest, Max, Allowed, Blocked, Acc);
    {_, false} ->
      take_ddg(Rest, Max, Allowed, Blocked, Acc);
    _ ->
      Title = string:trim(tag_strip(html_unescape(TitleHtml0))),
      Obj = #{
        title => Title,
        url => Url,
        content => null,
        source => <<"duckduckgo">>
      },
      take_ddg(Rest, Max, Allowed, Blocked, [Obj | Acc])
  end;
take_ddg([_ | Rest], Max, Allowed, Blocked, Acc) ->
  take_ddg(Rest, Max, Allowed, Blocked, Acc).

decode_ddg_redirect(Href0) ->
  Href = string:trim(to_bin(Href0)),
  case byte_size(Href) of
    0 -> Href;
    _ ->
      try
        M = uri_string:parse(binary_to_list(Href)),
        Qs0 = maps:get(query, M, undefined),
        case Qs0 of
          undefined -> Href;
          Qs ->
            Params = uri_string:dissect_query(Qs),
            case lists:keyfind("uddg", 1, Params) of
              false -> Href;
              {"uddg", U} -> to_bin(uri_string:percent_decode(U))
            end
        end
      catch
        _:_ -> Href
      end
  end.

domain_allowed(Url0, Allowed0, Blocked0) ->
  Url = to_bin(Url0),
  Allowed = [string:lowercase(to_bin(D)) || D <- Allowed0],
  Blocked = [string:lowercase(to_bin(D)) || D <- Blocked0],
  Host =
    try
      M = uri_string:parse(binary_to_list(Url)),
      H0 = maps:get(host, M, ""),
      string:lowercase(to_bin(H0))
    catch
      _:_ -> <<>>
    end,
  case byte_size(Host) of
    0 ->
      Allowed =:= [];
    _ ->
      case Blocked =/= [] andalso any_domain_match(Host, Blocked) of
        true -> false;
        false ->
          case Allowed =/= [] andalso not any_domain_match(Host, Allowed) of
            true -> false;
            false -> true
          end
      end
  end.

any_domain_match(_Host, []) -> false;
any_domain_match(Host, [D | Rest]) ->
  case Host =:= D orelse binary:match(Host, <<".", D/binary>>) =/= nomatch andalso ends_with(Host, <<".", D/binary>>) of
    true -> true;
    false -> any_domain_match(Host, Rest)
  end.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.

tag_strip(Html0) ->
  Html = to_bin(Html0),
  re:replace(Html, <<"<.*?>">>, <<>>, [global, {return, binary}]).

html_unescape(S0) ->
  S1 = binary:replace(to_bin(S0), <<"&amp;">>, <<"&">>, [global]),
  S2 = binary:replace(S1, <<"&lt;">>, <<"<">>, [global]),
  S3 = binary:replace(S2, <<"&gt;">>, <<">">>, [global]),
  S4 = binary:replace(S3, <<"&quot;">>, <<"\"">>, [global]),
  binary:replace(S4, <<"&#39;">>, <<"'">>, [global]).

urlencode(Bin0) ->
  Bin = to_bin(Bin0),
  uri_string:percent_encode(Bin, uri_string:urlchar_reserved()).

string_list(Input, KeyBin, KeyAtom) ->
  case maps:get(KeyBin, Input, maps:get(KeyAtom, Input, [])) of
    L when is_list(L) ->
      [string:lowercase(string:trim(to_bin(X))) || X <- L, byte_size(string:trim(to_bin(X))) > 0];
    _ ->
      []
  end.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_httpc_started() ->
  application:ensure_all_started(inets),
  application:ensure_all_started(ssl),
  _ = inets:start(httpc, [{profile, openagentic_websearch}, {data_dir, httpc_data_dir()}]),
  ok.

httpc_data_dir() ->
  case os:getenv("OPENAGENTIC_HTTPC_DATA_DIR") of
    false -> "E:/erlang/httpc";
    V -> to_list(V)
  end.

configure_proxy() ->
  ProxyUrl =
    first_env([
      "HTTPS_PROXY",
      "HTTP_PROXY",
      "https_proxy",
      "http_proxy"
    ]),
  case ProxyUrl of
    false -> ok;
    Url ->
      case parse_proxy_url(Url) of
        {ok, {Host, Port}} ->
          Opts = [
            {proxy, {{Host, Port}, []}},
            {https_proxy, {{Host, Port}, []}}
          ],
          _ = httpc:set_options(Opts, openagentic_websearch),
          ok;
        _ ->
          ok
      end
  end.

first_env([]) -> false;
first_env([K | T]) ->
  case os:getenv(K) of
    false -> first_env(T);
    "" -> first_env(T);
    V -> V
  end.

parse_proxy_url(Url0) ->
  Url = to_list(Url0),
  try
    M = uri_string:parse(Url),
    Host0 = maps:get(host, M, undefined),
    Port0 = maps:get(port, M, undefined),
    case Host0 of
      undefined -> {error, no_host};
      Host ->
        Port =
          case Port0 of
            undefined -> 7897;
            P when is_integer(P) -> P;
            PStr -> list_to_integer(PStr)
          end,
        {ok, {Host, Port}}
    end
  catch
    _:T -> {error, T}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
