-module(openagentic_tools_contract_test).

-include_lib("eunit/include/eunit.hrl").

todo_write_validates_and_reports_stats_test() ->
  {ok, Out} =
    openagentic_tool_todo_write:run(
      #{
        todos =>
          [
            #{
              <<"content">> => <<"do it">>,
              <<"status">> => <<"pending">>
            }
          ]
      },
      #{}
    ),
  ?assertEqual(<<"Updated todos">>, maps:get(message, Out)),
  Stats = maps:get(stats, Out),
  ?assertEqual(1, maps:get(total, Stats)),
  ?assertEqual(1, maps:get(pending, Stats)).

todo_write_rejects_empty_list_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"TodoWrite: 'todos' must be a non-empty list">>}} =
    openagentic_tool_todo_write:run(#{todos => []}, #{}).

notebook_edit_smoke_insert_then_delete_test() ->
  Root = test_root(),
  ProjectDir = Root,
  Path = filename:join([ProjectDir, "n.ipynb"]),
  %% Minimal ipynb: one cell with id "c1"
  Raw =
    <<
      "{",
      "\"cells\":[{",
      "\"cell_type\":\"code\",",
      "\"metadata\":{},",
      "\"source\":[\"print(1)\\n\"],",
      "\"id\":\"c1\"",
      "}],",
      "\"metadata\":{},",
      "\"nbformat\":4,",
      "\"nbformat_minor\":5",
      "}"
    >>,
  ok = file:write_file(Path, Raw),

  {ok, Out1} =
    openagentic_tool_notebook_edit:run(
      #{
        notebook_path => <<"n.ipynb">>,
        cell_id => <<"c1">>,
        edit_mode => <<"insert">>,
        new_source => <<"x=1">>
      },
      #{project_dir => ProjectDir}
    ),
  ?assertEqual(<<"inserted">>, maps:get(edit_type, Out1)),
  ?assert(maps:get(total_cells, Out1) >= 2),

  %% Delete the originally referenced cell id "c1"
  {ok, Out2} =
    openagentic_tool_notebook_edit:run(
      #{
        notebook_path => <<"n.ipynb">>,
        cell_id => <<"c1">>,
        edit_mode => <<"delete">>
      },
      #{project_dir => ProjectDir}
    ),
  ?assertEqual(<<"deleted">>, maps:get(edit_type, Out2)).

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
  restore_env("TAVILY_API_KEY", Old),
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
  restore_env("TAVILY_API_KEY", Old),
  ?assert(maps:is_key(meta, Out)),
  Results = maps:get(results, Out),
  ?assertEqual(1, length(Results)).

glob_root_missing_throws_file_not_found_exception_test() ->
  Root = test_root(),
  {error, {kotlin_error, <<"FileNotFoundException">>, Msg}} =
    openagentic_tool_glob:run(#{pattern => <<"**/*">>, root => <<"missing_dir">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Glob: not found:">>) =/= nomatch).

glob_root_not_directory_throws_illegal_argument_exception_test() ->
  Root = test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_glob:run(#{pattern => <<"**/*">>, root => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Glob: not a directory:">>) =/= nomatch).

grep_root_not_directory_throws_illegal_argument_exception_test() ->
  Root = test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_grep:run(#{query => <<"x">>, file_glob => <<"**/*">>, root => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Grep: not a directory:">>) =/= nomatch).

bash_workdir_not_directory_throws_illegal_argument_exception_test() ->
  Root = test_root(),
  Path = filename:join([Root, "f.txt"]),
  ok = file:write_file(Path, <<"x">>),
  {error, {kotlin_error, <<"IllegalArgumentException">>, Msg}} =
    openagentic_tool_bash:run(#{command => <<"echo hi">>, workdir => <<"f.txt">>}, #{project_dir => Root}),
  ?assert(binary:match(Msg, <<"Bash: not a directory:">>) =/= nomatch).

bash_requires_command_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Bash: 'command' must be a non-empty string">>}} =
    openagentic_tool_bash:run(#{command => <<"">>}, #{project_dir => "."}).

restore_env(Key, false) ->
  _ = os:unsetenv(Key),
  ok;
restore_env(Key, "") ->
  _ = os:putenv(Key, ""),
  ok;
restore_env(Key, V) ->
  _ = os:putenv(Key, V),
  ok.

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_tools_contract_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
