-module(openagentic_workflow_engine_output_helpers).
-export([missing_sections/2,has_section/2,re_escape/1,word_count/1,parse_json_object/1,strip_code_fences/1]).

missing_sections(Req0, Output0) ->
  Output = openagentic_workflow_engine_utils:to_bin(Output0),
  Req = [openagentic_workflow_engine_utils:to_bin(X) || X <- openagentic_workflow_engine_utils:ensure_list_value(Req0)],
  [R || R <- Req, not has_section(R, Output)].

has_section(Title0, Output0) ->
  Title = string:trim(openagentic_workflow_engine_utils:to_bin(Title0)),
  Output = openagentic_workflow_engine_utils:to_bin(Output0),
  case byte_size(Title) of
    0 -> true;
    _ ->
      Pat = iolist_to_binary([<<"(?m)^\\s*#+\\s+">>, re_escape(Title), <<"\\s*$">>]),
      case (catch re:run(Output, Pat, [{capture, none}, unicode])) of
        match -> true;
        _ -> false
      end
  end.

re_escape(Bin0) ->
  Bin = openagentic_workflow_engine_utils:to_bin(Bin0),
  lists:foldl(
    fun ({From, To}, Acc) -> binary:replace(Acc, From, To, [global]) end,
    Bin,
    [
      {<<"\\">>, <<"\\\\">>},
      {<<".">>, <<"\\.">>},
      {<<"+">>, <<"\\+">>},
      {<<"*">>, <<"\\*">>},
      {<<"?">>, <<"\\?">>},
      {<<"^">>, <<"\\^">>},
      {<<"$">>, <<"\\$">>},
      {<<"(">>, <<"\\(">>},
      {<<")">>, <<"\\)">>},
      {<<"[">>, <<"\\[">>},
      {<<"]">>, <<"\\]">>},
      {<<"{">>, <<"\\{">>},
      {<<"}">>, <<"\\}">>},
      {<<"|">>, <<"\\|">>}
    ]
  ).

word_count(Text0) ->
  Text = openagentic_workflow_engine_utils:to_bin(Text0),
  Parts = re:split(Text, <<"\\s+">>, [unicode, {return, list}]),
  length([P || P <- Parts, string:trim(P) =/= ""]).

parse_json_object(Output0) ->
  Output = string:trim(openagentic_workflow_engine_utils:to_bin(Output0)),
  Bin = strip_code_fences(Output),
  try
    Obj = openagentic_json:decode(Bin),
    case is_map(Obj) of
      true -> {ok, Obj};
      false -> {error, not_object}
    end
  catch
    _:_ -> {error, invalid_json}
  end.

strip_code_fences(Bin0) ->
  Bin = openagentic_workflow_engine_utils:to_bin(Bin0),
  case re:run(Bin, <<"(?s)^```[a-zA-Z0-9_-]*\\s*(\\{.*\\})\\s*```\\s*$">>, [{capture, [1], binary}, unicode]) of
    {match, [Inner]} -> Inner;
    _ -> Bin
  end.

%% ---- sessions & workflow events ----
