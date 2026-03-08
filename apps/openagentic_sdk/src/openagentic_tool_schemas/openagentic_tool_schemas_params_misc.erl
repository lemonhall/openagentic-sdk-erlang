-module(openagentic_tool_schemas_params_misc).

-export([tool_params/2]).

tool_params(_Mod, <<"lsp">>) ->
  #{
    type => <<"object">>,
    properties => #{
      operation => #{type => <<"string">>, enum => [<<"goToDefinition">>, <<"findReferences">>, <<"hover">>, <<"documentSymbol">>, <<"workspaceSymbol">>, <<"goToImplementation">>, <<"prepareCallHierarchy">>, <<"incomingCalls">>, <<"outgoingCalls">>]},
      filePath => #{type => <<"string">>},
      file_path => #{type => <<"string">>},
      line => #{type => <<"integer">>, minimum => 1},
      character => #{type => <<"integer">>, minimum => 1}
    },
    required => [<<"operation">>, <<"filePath">>, <<"line">>, <<"character">>]
  };
tool_params(_Mod, _Name) ->
  #{type => <<"object">>, properties => #{}, required => []}.
