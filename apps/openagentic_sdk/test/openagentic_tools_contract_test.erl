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

websearch_requires_query_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebSearch: 'query' must be a non-empty string">>}} =
    openagentic_tool_websearch:run(#{query => <<"">>}, #{}).

bash_requires_command_test() ->
  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Bash: 'command' must be a non-empty string">>}} =
    openagentic_tool_bash:run(#{command => <<"">>}, #{project_dir => "."}).

test_root() ->
  Base = code:lib_dir(openagentic_sdk),
  Tmp = filename:join([Base, "tmp", integer_to_list(erlang:unique_integer([positive]))]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.

