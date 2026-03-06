-module(openagentic_task_agents).

-export([
  normalize/1,
  has_agent/2,
  render_agents_for_prompt/1
]).

normalize(Agents0) ->
  Agents = ensure_list(Agents0),
  lists:filtermap(fun normalize_one/1, Agents).

normalize_one(<<"explore">>) -> {true, openagentic_built_in_subagents:explore_agent()};
normalize_one("explore") -> {true, openagentic_built_in_subagents:explore_agent()};
normalize_one(explore) -> {true, openagentic_built_in_subagents:explore_agent()};
normalize_one(<<"research">>) -> {true, openagentic_built_in_subagents:research_agent()};
normalize_one("research") -> {true, openagentic_built_in_subagents:research_agent()};
normalize_one(research) -> {true, openagentic_built_in_subagents:research_agent()};
normalize_one(A) when is_binary(A); is_list(A); is_atom(A) ->
  Name = string:trim(to_bin(A)),
  case byte_size(Name) > 0 of
    false -> false;
    true -> {true, #{name => Name, description => <<>>, allowed_tools => []}}
  end;
normalize_one(M0) when is_map(M0) ->
  M = ensure_map(M0),
  Name0 = maps:get(name, M, maps:get(<<"name">>, M, undefined)),
  Name = string:trim(to_bin(Name0)),
  case byte_size(Name) > 0 of
    false ->
      false;
    true ->
      Base =
        case string:lowercase(Name) of
          <<"explore">> -> openagentic_built_in_subagents:explore_agent();
          <<"research">> -> openagentic_built_in_subagents:research_agent();
          _ -> #{name => Name, description => <<>>, allowed_tools => []}
        end,
      Desc0 = maps:get(description, M, maps:get(<<"description">>, M, maps:get(desc, M, maps:get(<<"desc">>, M, undefined)))),
      Desc = string:trim(to_bin(Desc0)),
      Tools0 =
        maps:get(
          allowed_tools,
          M,
          maps:get(
            allowedTools,
            M,
            maps:get(<<"allowed_tools">>, M, maps:get(<<"allowedTools">>, M, maps:get(tools, M, maps:get(<<"tools">>, M, []))))
          )
        ),
      Tools = [string:trim(to_bin(T)) || T <- ensure_list(Tools0), byte_size(string:trim(to_bin(T))) > 0],
      {true, Base#{description => Desc, allowed_tools => Tools}}
  end;
normalize_one(_) ->
  false.

has_agent(Name0, Agents0) ->
  Name = string:lowercase(string:trim(to_bin(Name0))),
  lists:any(
    fun (A0) ->
      A = ensure_map(A0),
      N = string:lowercase(string:trim(to_bin(maps:get(name, A, maps:get(<<"name">>, A, <<>>))))),
      N =:= Name
    end,
    normalize(Agents0)
  ).

render_agents_for_prompt(Agents0) ->
  Agents = normalize(Agents0),
  case Agents of
    [] ->
      <<"  (none configured)">>;
    _ ->
      Lines = [render_one_agent(A) || A <- Agents],
      iolist_to_binary(lists:join(<<"\n">>, Lines))
  end.

render_one_agent(A0) ->
  A = ensure_map(A0),
  Name = string:trim(to_bin(maps:get(name, A, maps:get(<<"name">>, A, <<>>)))),
  Desc0 = string:trim(to_bin(maps:get(description, A, maps:get(<<"description">>, A, <<>>)))),
  Desc = case byte_size(Desc0) > 0 of true -> Desc0; false -> <<"No description.">> end,
  Tools0 = ensure_list(maps:get(allowed_tools, A, maps:get(<<"allowed_tools">>, A, maps:get(allowedTools, A, maps:get(<<"allowedTools">>, A, []))))),
  Tools = [string:trim(to_bin(T)) || T <- Tools0, byte_size(string:trim(to_bin(T))) > 0],
  ToolsPart =
    case Tools of
      [] -> <<>>;
      _ -> iolist_to_binary([<<" (tools: ">>, join_csv(Tools), <<")">>])
    end,
  iolist_to_binary([<<"- ">>, Name, <<": ">>, Desc, ToolsPart]).

join_csv([]) -> <<>>;
join_csv([One]) -> One;
join_csv([H | T]) -> iolist_to_binary([H, <<", ">>, join_csv(T)]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [B];
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
