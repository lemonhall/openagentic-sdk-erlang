-module(openagentic_tools_contract_webfetch_test).

-include_lib("eunit/include/eunit.hrl").

webfetch_rejects_non_http_url_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: only http/https URLs are allowed">>}} =
    openagentic_tool_webfetch:run(#{url => <<"file:///etc/passwd">>}, #{}).

webfetch_blocks_ipv6_loopback_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>}} =
    openagentic_tool_webfetch:run(#{url => <<"http://[::1]/">>}, #{}).

webfetch_blocks_dot_localhost_suffix_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>}} =
    openagentic_tool_webfetch:run(#{url => <<"http://x.localhost/">>}, #{}).

webfetch_blocks_ipv4_private_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>}} =
    openagentic_tool_webfetch:run(#{url => <<"http://192.168.0.1/">>}, #{}).

webfetch_blocks_ipv6_ula_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>}} =
    openagentic_tool_webfetch:run(#{url => <<"http://[fc00::1]/">>}, #{}).

webfetch_markdown_sanitizes_and_absolutizes_links_test() ->
  Html =
    <<
      "<html><head><title>T</title></head><body>",
      "<nav>nav <a href=\"/n\">n</a></nav>",
      "<article><h1>Title</h1><p>Hello <a href=\"/rel\">Link</a></p></article>",
      "<script>bad()</script>",
      "</body></html>"
    >>,
  Transport =
    fun (_Url, _Headers) ->
      {ok, {200, #{<<"content-type">> => <<"text/html">>}, Html}}
    end,
  {ok, Out} =
    openagentic_tool_webfetch:run(
      #{url => <<"https://example.com/x">>, mode => <<"markdown">>},
      #{webfetch_transport => Transport}
    ),
  ?assertEqual(<<"T">>, maps:get(title, Out)),
  ?assertEqual(<<"# Title\n\nHello [Link](https://example.com/rel)">>, maps:get(text, Out)).

webfetch_clean_html_returns_allowlisted_html_test() ->
  Html =
    <<
      "<html><body>",
      "<article><h1>Title</h1><p>Hello <a href=\"/rel\">Link</a></p></article>",
      "</body></html>"
    >>,
  Transport =
    fun (_Url, _Headers) ->
      {ok, {200, #{}, Html}}
    end,
  {ok, Out} =
    openagentic_tool_webfetch:run(
      #{url => <<"https://example.com/x">>, mode => <<"clean_html">>},
      #{webfetch_transport => Transport}
    ),
  ?assertEqual(<<"<h1>Title</h1>\n<p>Hello <a href=\"https://example.com/rel\">Link</a></p>">>, maps:get(text, Out)).

webfetch_markdown_falls_back_to_tavily_extract_on_js_shell_test() ->
  Html = <<"<html><head><title>Just a moment...</title></head><body>Just a moment...</body></html>">>,
  Transport =
    fun (_Url, _Headers) ->
      {ok, {403, #{<<"content-type">> => <<"text/html">>}, Html}}
    end,
  HttpTransport =
    fun (post, Url, Headers, Body) ->
      ?assertEqual(<<"https://api.tavily.com/extract">>, iolist_to_binary(Url)),
      ?assertEqual(true, lists:keymember("authorization", 1, Headers)),
      Payload = openagentic_json:decode(iolist_to_binary(Body)),
      ?assertEqual(<<"https://example.com/x">>, maps:get(<<"urls">>, Payload)),
      ?assertEqual(<<"markdown">>, maps:get(<<"format">>, Payload)),
      Resp =
        openagentic_json:encode(
          #{
            results => [
              #{
                url => <<"https://example.com/x">>,
                title => <<"Recovered">>,
                raw_content => <<"# Recovered\n\nBody from Tavily.\n\n- Fact A">>
              }
            ]
          }
        ),
      {ok, {200, [], Resp}}
    end,
  {ok, Out} =
    openagentic_tool_webfetch:run(
      #{url => <<"https://example.com/x">>, mode => <<"markdown">>},
      #{
        webfetch_transport => Transport,
        webfetch_http_transport => HttpTransport,
        tavily_api_key => <<"test-tavily-key">>
      }
    ),
  ?assertEqual(<<"tavily_extract">>, maps:get(fetch_via, Out)),
  ?assertEqual(403, maps:get(origin_status, Out)),
  ?assertEqual(200, maps:get(status, Out)),
  ?assertEqual(<<"Recovered">>, maps:get(title, Out)),
  ?assert(binary:match(maps:get(text, Out), <<"Body from Tavily.">>) =/= nomatch).
