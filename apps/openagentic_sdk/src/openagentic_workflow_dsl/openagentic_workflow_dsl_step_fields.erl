-module(openagentic_workflow_dsl_step_fields).
-export([validate_fanout/3, validate_input_binding/3, validate_output_contract/3, validate_prompt_ref/4]).

validate_fanout(Path, Fanout0, Errors0) ->
  {Fanout, Errors1} = openagentic_workflow_dsl_utils:require_map(Path, Fanout0, <<"fanout is required">>, Errors0),
  Steps0 = openagentic_workflow_dsl_utils:get_any(Fanout, [<<"steps">>, steps], undefined),
  {Steps, Errors2} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".steps">>]), Steps0, <<"fanout.steps must be an array">>, Errors1),
  Errors3 = case Steps of [] -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".steps">>]), <<"empty">>, <<"fanout.steps must be non-empty">>) | Errors2]; _ -> Errors2 end,
  FanoutSteps = [openagentic_workflow_dsl_utils:to_bin(StepId) || StepId <- Steps],
  Errors4 = case lists:all(fun is_binary/1, FanoutSteps) of true -> Errors3; false -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".steps">>]), <<"invalid_type">>, <<"fanout.steps must contain strings">>) | Errors3] end,
  Join = openagentic_workflow_dsl_utils:get_nullable_step_ref(Fanout, [<<"join">>, join]),
  Errors5 = case Join of undefined -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".join">>]), <<"missing">>, <<"fanout.join is required">>) | Errors4]; _ -> Errors4 end,
  _MaxConcurrency = openagentic_workflow_dsl_utils:get_any(Fanout, [<<"max_concurrency">>, max_concurrency], undefined),
  _FailFast = openagentic_workflow_dsl_utils:get_any(Fanout, [<<"fail_fast">>, fail_fast], undefined),
  {FanoutSteps, Join, Errors5}.

validate_input_binding(Path, Input, Errors0) ->
  T = openagentic_workflow_dsl_utils:get_bin(Input, [<<"type">>, type], <<>>),
  case T of
    <<"controller_input">> -> Errors0;
    <<"step_output">> ->
      StepId = openagentic_workflow_dsl_utils:get_bin(Input, [<<"step_id">>, step_id], <<>>),
      openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".step_id">>]), StepId, <<"step_id is required">>, Errors0);
    <<"merge">> ->
      Sources0 = openagentic_workflow_dsl_utils:get_any(Input, [<<"sources">>, sources], undefined),
      {Sources, Errors1} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".sources">>]), Sources0, <<"sources must be an array">>, Errors0),
      case Sources of [] -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".sources">>]), <<"empty">>, <<"sources must be non-empty">>) | Errors1]; _ -> Errors1 end;
    <<>> -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"input.type is required">>) | Errors0];
    _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"unknown_input_type">>, iolist_to_binary([<<"unknown input type: ">>, T])) | Errors0]
  end.

validate_prompt_ref(ProjectDir, Path, Prompt, Errors0) ->
  T = openagentic_workflow_dsl_utils:get_bin(Prompt, [<<"type">>, type], <<>>),
  case T of
    <<"inline">> ->
      Txt = openagentic_workflow_dsl_utils:get_bin(Prompt, [<<"text">>, text], <<>>),
      openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".text">>]), Txt, <<"prompt.text is required">>, Errors0);
    <<"file">> ->
      P = openagentic_workflow_dsl_utils:get_bin(Prompt, [<<"path">>, path], <<>>),
      Errors1 = openagentic_workflow_dsl_utils:require_nonempty_bin(iolist_to_binary([Path, <<".path">>]), P, <<"prompt.path is required">>, Errors0),
      case P of
        <<>> -> Errors1;
        _ ->
          case openagentic_fs:resolve_project_path(ProjectDir, P) of
            {ok, Abs} ->
              case filelib:is_file(Abs) of
                true -> Errors1;
                false -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".path">>]), <<"missing_file">>, <<"prompt file does not exist">>) | Errors1]
              end;
            {error, unsafe_path} -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".path">>]), <<"unsafe_path">>, <<"prompt path is unsafe">>) | Errors1]
          end
      end;
    <<>> -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"prompt.type is required">>) | Errors0];
    _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"unknown_prompt_type">>, iolist_to_binary([<<"unknown prompt type: ">>, T])) | Errors0]
  end.

validate_output_contract(Path, OutC, Errors0) ->
  T = openagentic_workflow_dsl_utils:get_bin(OutC, [<<"type">>, type], <<>>),
  case T of
    <<"markdown_sections">> ->
      Req0 = openagentic_workflow_dsl_utils:get_any(OutC, [<<"required">>, required], undefined),
      {Req, Errors1} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".required">>]), Req0, <<"required must be an array">>, Errors0),
      case Req of [] -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".required">>]), <<"empty">>, <<"required must be non-empty">>) | Errors1]; _ -> Errors1 end;
    <<"decision">> ->
      Allowed0 = openagentic_workflow_dsl_utils:get_any(OutC, [<<"allowed">>, allowed], undefined),
      {_Allowed, Errors1} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".allowed">>]), Allowed0, <<"allowed must be an array">>, Errors0),
      Fmt = openagentic_workflow_dsl_utils:get_bin(OutC, [<<"format">>, format], <<>>),
      Errors2 = case Fmt of <<>> -> Errors1; <<"json">> -> Errors1; _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".format">>]), <<"invalid_format">>, <<"decision.format must be json">>) | Errors1] end,
      Fields0 = openagentic_workflow_dsl_utils:get_any(OutC, [<<"fields">>, fields], undefined),
      {_Fields, Errors3} = openagentic_workflow_dsl_utils:require_list(iolist_to_binary([Path, <<".fields">>]), Fields0, <<"fields must be an array">>, Errors2),
      Errors3;
    <<"json_object">> -> Errors0;
    <<>> -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"missing">>, <<"output_contract.type is required">>) | Errors0];
    _ -> [openagentic_workflow_dsl_utils:err(iolist_to_binary([Path, <<".type">>]), <<"unknown_output_contract_type">>, iolist_to_binary([<<"unknown output_contract type: ">>, T])) | Errors0]
  end.
