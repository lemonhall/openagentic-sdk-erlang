-module(openagentic_e2e_online_assert).
-export([
  assert_ok_non_empty/2,
  assert_ok_text_contains/3,
  events_summary/1,
  first_error/1,
  has_event_type/2,
  is_allowed_warn/1,
  tool_events_ok_with_results/2
]).

assert_ok_non_empty(Tag, Res) ->
  case Res of
    {ok, #{final_text := Txt}} ->
      case byte_size(string:trim(openagentic_e2e_online_utils:to_bin(Txt))) > 0 of
        true -> ok;
        false -> {error, {Tag, empty_text}}
      end;
    Other ->
      {error, {Tag, Other}}
  end.

assert_ok_text_contains(Tag, Res, Needle) ->
  case Res of
    {ok, #{final_text := Txt}} ->
      Text = openagentic_e2e_online_utils:to_bin(Txt),
      case binary:match(string:lowercase(Text), string:lowercase(openagentic_e2e_online_utils:to_bin(Needle))) of
        nomatch -> {error, {Tag, not_found}};
        _ -> ok
      end;
    Other ->
      {error, {Tag, Other}}
  end.

first_error([]) -> ok;
first_error([ok | Rest]) -> first_error(Rest);
first_error([Err | _]) -> Err.

has_event_type(Events, Type) ->
  lists:any(fun (Ev0) -> event_type(Ev0) =:= Type end, openagentic_e2e_online_utils:ensure_list(Events)).

event_type(Ev0) ->
  Ev = openagentic_e2e_online_utils:ensure_map(Ev0),
  openagentic_e2e_online_utils:to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))).

tool_events_ok_with_results(Events0, ToolNames0) ->
  Events = openagentic_e2e_online_utils:ensure_list(Events0),
  ToolNames = [openagentic_e2e_online_utils:to_bin(N) || N <- openagentic_e2e_online_utils:ensure_list(ToolNames0)],
  UsePairs =
    [
      {openagentic_e2e_online_utils:to_bin(maps:get(name, E)), openagentic_e2e_online_utils:to_bin(maps:get(tool_use_id, E))}
    ||
      E0 <- Events,
      E <- [openagentic_e2e_online_utils:ensure_map(E0)],
      event_type(E) =:= <<"tool.use">>,
      maps:is_key(name, E),
      maps:is_key(tool_use_id, E)
    ],
  UsedNames = lists:usort([N || {N, _} <- UsePairs]),
  Missing = [N || N <- ToolNames, not lists:member(N, UsedNames)],
  case Missing of
    [] ->
      OkResultIds =
        lists:usort(
          [
            openagentic_e2e_online_utils:to_bin(maps:get(tool_use_id, E))
          ||
            E0 <- Events,
            E <- [openagentic_e2e_online_utils:ensure_map(E0)],
            event_type(E) =:= <<"tool.result">>,
            maps:get(is_error, E, true) =:= false,
            maps:is_key(tool_use_id, E)
          ]
        ),
      Bad =
        [
          #{tool => ToolName, error => missing_ok_result}
        ||
          ToolName <- ToolNames,
          not lists:any(fun ({N, Id}) -> N =:= ToolName andalso lists:member(Id, OkResultIds) end, UsePairs)
        ],
      case Bad of
        [] -> ok;
        _ -> {error, #{error => tool_result_missing_or_error, details => Bad}}
      end;
    _ ->
      {error, #{error => missing_tool_use_events, missing => Missing, used => UsedNames, summary => events_summary(Events)}}
  end.

is_allowed_warn({warn, {streaming_no_deltas, _}}) -> true;
is_allowed_warn(_) -> false.

events_summary(Events) ->
  Types = [event_type(E) || E <- openagentic_e2e_online_utils:ensure_list(Events)],
  lists:usort(Types).
