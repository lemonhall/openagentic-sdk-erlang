-module(openagentic_tool_schemas_params_fs).

-export([tool_params/2]).

tool_params(_Mod, <<"Read">>) ->
  #{type => <<"object">>, properties => #{file_path => #{type => <<"string">>}, filePath => #{type => <<"string">>}, offset => #{type => <<"integer">>}, limit => #{type => <<"integer">>}}, required => []};
tool_params(_Mod, <<"List">>) ->
  #{type => <<"object">>, properties => #{path => #{type => <<"string">>}, dir => #{type => <<"string">>}, directory => #{type => <<"string">>}}, required => []};
tool_params(_Mod, <<"Write">>) ->
  #{type => <<"object">>, properties => #{file_path => #{type => <<"string">>}, filePath => #{type => <<"string">>}, content => #{type => <<"string">>}, overwrite => #{type => <<"boolean">>}}, required => []};
tool_params(_Mod, <<"Edit">>) ->
  #{type => <<"object">>, properties => #{file_path => #{type => <<"string">>}, filePath => #{type => <<"string">>}, old => #{type => <<"string">>}, new => #{type => <<"string">>}, old_string => #{type => <<"string">>}, new_string => #{type => <<"string">>}, oldString => #{type => <<"string">>}, newString => #{type => <<"string">>}, count => #{type => <<"integer">>}, replace_all => #{type => <<"boolean">>}, replaceAll => #{type => <<"boolean">>}, before => #{type => <<"string">>}, 'after' => #{type => <<"string">>}}, required => []};
tool_params(_Mod, <<"Glob">>) ->
  #{type => <<"object">>, properties => #{pattern => #{type => <<"string">>}, root => #{type => <<"string">>}, path => #{type => <<"string">>}}, required => [<<"pattern">>]};
tool_params(_Mod, <<"Grep">>) ->
  #{type => <<"object">>, properties => #{query => #{type => <<"string">>}, file_glob => #{type => <<"string">>}, root => #{type => <<"string">>}, path => #{type => <<"string">>}, case_sensitive => #{type => <<"boolean">>}, mode => #{type => <<"string">>, enum => [<<"content">>, <<"files_with_matches">>]}}, required => [<<"query">>]};
tool_params(_Mod, <<"Bash">>) ->
  #{type => <<"object">>, properties => #{command => #{type => <<"string">>}, workdir => #{type => <<"string">>}, timeout => #{type => <<"integer">>}, timeout_s => #{type => <<"number">>}}, required => [<<"command">>]};
tool_params(_Mod, <<"NotebookEdit">>) ->
  #{type => <<"object">>, properties => #{notebook_path => #{type => <<"string">>}, cell_id => #{type => <<"string">>}, new_source => #{type => <<"string">>}, cell_type => #{type => <<"string">>, enum => [<<"code">>, <<"markdown">>]}, edit_mode => #{type => <<"string">>, enum => [<<"replace">>, <<"insert">>, <<"delete">>]}}, required => [<<"notebook_path">>]};
tool_params(_Mod, _Name) ->
  undefined.
