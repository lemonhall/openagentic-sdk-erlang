-module(openagentic_anthropic_parsing_tools).

-export([responses_tools_to_anthropic_tools/1]).

responses_tools_to_anthropic_tools(Tools0) ->
  Tools = openagentic_anthropic_parsing_utils:ensure_list(Tools0),
  lists:filtermap(
    fun (T0) ->
      T = openagentic_anthropic_parsing_utils:ensure_map(T0),
      Name = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(T, [<<"name">>, name])),
      case byte_size(Name) > 0 of
        false -> false;
        true ->
          Desc = openagentic_anthropic_parsing_utils:bin_trim(openagentic_anthropic_parsing_utils:pick_first(T, [<<"description">>, description])),
          Params0 = openagentic_anthropic_parsing_utils:pick_first(T, [<<"parameters">>, parameters]),
          Params = case Params0 of M when is_map(M) -> M; _ -> #{<<"type">> => <<"object">>, <<"properties">> => #{}} end,
          Tool0 = #{<<"name">> => Name, <<"input_schema">> => Params},
          Tool = case byte_size(Desc) > 0 of true -> Tool0#{<<"description">> => Desc}; false -> Tool0 end,
          {true, Tool}
      end
    end,
    Tools
  ).
