-module(openagentic_tool_schemas_params_web).

-export([tool_params/2]).

tool_params(_Mod, <<"WebSearch">>) ->
  #{type => <<"object">>, properties => #{query => #{type => <<"string">>}, max_results => #{type => <<"integer">>}, allowed_domains => #{type => <<"array">>, items => #{type => <<"string">>}}, blocked_domains => #{type => <<"array">>, items => #{type => <<"string">>}}}, required => [<<"query">>]};
tool_params(_Mod, <<"WebFetch">>) ->
  #{type => <<"object">>, properties => #{url => #{type => <<"string">>}, headers => #{type => <<"object">>}, mode => #{type => <<"string">>, enum => [<<"markdown">>, <<"clean_html">>, <<"text">>, <<"raw">>]}, max_chars => #{type => <<"integer">>, minimum => 1000, maximum => 80000}, prompt => #{type => <<"string">>}}, required => [<<"url">>]};
tool_params(_Mod, _Name) ->
  undefined.
