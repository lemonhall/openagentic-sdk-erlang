-module(openagentic_workflow_engine_prompts).
-export([resolve_prompt/2,bind_input/2,maybe_filter_tasks_input/2,is_ministry_role/1,merge_sources/4,build_user_prompt/5]).

resolve_prompt(State0, StepRaw) ->
  Prompt0 = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"prompt">>, prompt], #{})),
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Prompt0, [<<"type">>, type], <<>>)),
  ProjectDir = maps:get(project_dir, State0),
  case T of
    <<"inline">> ->
      Txt = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Prompt0, [<<"text">>, text], <<>>)),
      case byte_size(string:trim(Txt)) > 0 of
        true -> {ok, Txt};
        false -> {error, <<"prompt.text is required">>}
      end;
    <<"file">> ->
      Rel = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Prompt0, [<<"path">>, path], <<>>)),
      case openagentic_fs:resolve_project_path(ProjectDir, Rel) of
        {ok, Abs} ->
          case file:read_file(Abs) of
            {ok, Bin} -> {ok, Bin};
            _ -> {error, <<"prompt file read failed">>}
          end;
        _ ->
          {error, <<"prompt path unsafe">>}
      end;
    _ ->
      {error, <<"unknown prompt type">>}
  end.

bind_input(State0, StepRaw) ->
  Input0 = openagentic_workflow_engine_utils:ensure_map(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"input">>, input], #{})),
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Input0, [<<"type">>, type], <<>>)),
  Role = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(StepRaw, [<<"role">>, role], <<>>)),
  StepOutputs = maps:get(step_outputs, State0, #{}),
  case T of
    <<"controller_input">> ->
      maps:get(controller_input, State0, <<>>);
    <<"step_output">> ->
      From = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Input0, [<<"step_id">>, step_id], <<>>)),
      case maps:get(From, StepOutputs, undefined) of
        #{output := Out} -> maybe_filter_tasks_input(Role, openagentic_workflow_engine_utils:to_bin(Out));
        _ -> <<>>
      end;
    <<"merge">> ->
      Sources = openagentic_workflow_engine_utils:ensure_list_value(openagentic_workflow_engine_utils:get_any(Input0, [<<"sources">>, sources], [])),
      merge_sources(Sources, StepOutputs, 0, []);
    _ ->
      <<>>
  end.

maybe_filter_tasks_input(Role, OutBin) ->
  case is_ministry_role(Role) of
    false ->
      OutBin;
    true ->
      case (catch openagentic_json:decode(OutBin)) of
        #{<<"tasks">> := Tasks0} = Obj when is_list(Tasks0) ->
          Tasks =
            [
              T0
              || T0 <- Tasks0,
                 is_map(T0),
                 openagentic_workflow_engine_utils:to_bin(maps:get(<<"ministry">>, T0, maps:get(ministry, T0, <<>>))) =:= Role
            ],
          %% Keep all other keys intact, only filter `tasks`.
          openagentic_json:encode(Obj#{<<"tasks">> => Tasks});
        _ ->
          OutBin
      end
  end.

is_ministry_role(<<"hubu">>) -> true;
is_ministry_role(<<"libu">>) -> true;
is_ministry_role(<<"bingbu">>) -> true;
is_ministry_role(<<"xingbu">>) -> true;
is_ministry_role(<<"gongbu">>) -> true;
is_ministry_role(<<"libu_hr">>) -> true;
is_ministry_role(_) -> false.

merge_sources([], _StepOutputs, _Idx, AccRev) ->
  iolist_to_binary(lists:reverse(AccRev));
merge_sources([Src0 | Rest], StepOutputs, Idx, AccRev) ->
  Src = openagentic_workflow_engine_utils:ensure_map(Src0),
  T = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Src, [<<"type">>, type], <<>>)),
  Chunk =
    case T of
      <<"step_output">> ->
        Sid = openagentic_workflow_engine_utils:to_bin(openagentic_workflow_engine_utils:get_any(Src, [<<"step_id">>, step_id], <<>>)),
        case maps:get(Sid, StepOutputs, undefined) of
          #{output := Out} -> openagentic_workflow_engine_utils:to_bin(Out);
          _ -> <<>>
        end;
      <<"controller_input">> ->
        <<>>;
      _ ->
        <<>>
    end,
  case byte_size(string:trim(Chunk)) > 0 of
    false ->
      merge_sources(Rest, StepOutputs, Idx, AccRev);
    true ->
      Header = iolist_to_binary([<<"\n\n--- source ">>, integer_to_binary(Idx + 1), <<" (">>, T, <<") ---\n\n">>]),
      merge_sources(Rest, StepOutputs, Idx + 1, [Chunk, Header | AccRev])
  end.

build_user_prompt(PromptText, ControllerText0, InputText0, _Attempt0, Failures0) ->
  Failures = [openagentic_workflow_engine_utils:to_bin(X) || X <- openagentic_workflow_engine_utils:ensure_list_value(Failures0)],
  ControllerText = openagentic_workflow_engine_utils:to_bin(ControllerText0),
  InputText = openagentic_workflow_engine_utils:to_bin(InputText0),
  %% IMPORTANT: Keep these separators ASCII-only so the assembled prompt is always valid UTF-8.
  %% Otherwise, session persistence may sanitize it into a byte dump (<<...>>) and the model
  %% won't see the real user intent.
  Base =
    iolist_to_binary([
      PromptText,
      <<"\n\n---\n\n# Controller\n\n">>,
      ControllerText,
      <<"\n\n---\n\n# Input\n\n">>,
      InputText,
      <<"\n">>
    ]),
  case Failures =/= [] of
    true ->
      Hint =
        iolist_to_binary([
          <<"\n\n---\n\n# Previous failure reasons (must fix)\n\n">>,
          <<"- ">>, openagentic_workflow_engine_utils:join_bins(Failures, <<"\n- ">>), <<"\n\n">>,
          <<"Fix the above reasons and re-output strictly; do NOT ask questions; do NOT change required headings.\n">>
        ]),
      iolist_to_binary([Base, Hint]);
    false ->
      Base
  end.
