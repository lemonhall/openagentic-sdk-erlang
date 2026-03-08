-module(openagentic_tools_contract_todo_notebook_test).

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
  Root = openagentic_tools_contract_test_support:test_root(),
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
