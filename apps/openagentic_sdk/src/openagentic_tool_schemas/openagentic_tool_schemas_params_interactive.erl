-module(openagentic_tool_schemas_params_interactive).

-export([tool_params/2]).

tool_params(_Mod, <<"AskUserQuestion">>) ->
  #{
    type => <<"object">>,
    properties => #{
      questions =>
        #{
          type => <<"array">>,
          items =>
            #{
              type => <<"object">>,
              properties => #{
                question => #{type => <<"string">>},
                header => #{type => <<"string">>},
                options => #{type => <<"array">>, items => #{type => <<"object">>, properties => #{label => #{type => <<"string">>}, description => #{type => <<"string">>}}, required => [<<"label">>] }},
                multiple => #{type => <<"boolean">>},
                multiSelect => #{type => <<"boolean">>}
              },
              required => [<<"question">>]
            }
        },
      question => #{type => <<"string">>},
      options => #{type => <<"array">>, items => #{type => <<"string">>}},
      choices => #{type => <<"array">>, items => #{type => <<"string">>}},
      answers => #{type => <<"object">>}
    },
    required => []
  };
tool_params(_Mod, <<"Skill">>) ->
  #{type => <<"object">>, properties => #{name => #{type => <<"string">>}}, required => [<<"name">>]};
tool_params(_Mod, <<"SlashCommand">>) ->
  #{type => <<"object">>, properties => #{name => #{type => <<"string">>}, args => #{type => <<"string">>}, arguments => #{type => <<"string">>}, project_dir => #{type => <<"string">>}}, required => [<<"name">>]};
tool_params(_Mod, <<"Task">>) ->
  #{type => <<"object">>, properties => #{agent => #{type => <<"string">>}, prompt => #{type => <<"string">>}}, required => [<<"agent">>, <<"prompt">>]};
tool_params(_Mod, <<"TodoWrite">>) ->
  #{
    type => <<"object">>,
    properties => #{
      todos =>
        #{
          type => <<"array">>,
          items => #{type => <<"object">>, properties => #{content => #{type => <<"string">>}, status => #{type => <<"string">>, enum => [<<"pending">>, <<"in_progress">>, <<"completed">>]}, activeForm => #{type => <<"string">>}}, required => [<<"content">>, <<"status">>, <<"activeForm">>]}
        }
    },
    required => [<<"todos">>]
  };
tool_params(_Mod, _Name) ->
  undefined.
