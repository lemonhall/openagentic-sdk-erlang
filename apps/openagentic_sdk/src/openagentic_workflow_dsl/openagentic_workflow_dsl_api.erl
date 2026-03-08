-module(openagentic_workflow_dsl_api).
-export([load/3, load_and_validate/3, validate/3]).

load(ProjectDir0, RelPath0, Opts0) ->
  ProjectDir = openagentic_workflow_dsl_utils:ensure_list(ProjectDir0),
  RelPath = openagentic_workflow_dsl_utils:ensure_list(RelPath0),
  _Opts = openagentic_workflow_dsl_utils:ensure_map(Opts0),
  case openagentic_fs:resolve_project_path(ProjectDir, RelPath) of
    {ok, AbsPath} ->
      case file:read_file(AbsPath) of
        {ok, Bin} ->
          try
            Obj = openagentic_json:decode(Bin),
            case is_map(Obj) of
              true -> {ok, Obj};
              false -> {error, {invalid_workflow_dsl, [openagentic_workflow_dsl_utils:err(<<"$">>, <<"not_object">>, <<"workflow must be a JSON object">>)]}}
            end
          catch
            _:_ ->
              {error, {invalid_workflow_dsl, [openagentic_workflow_dsl_utils:err(<<"$">>, <<"invalid_json">>, <<"workflow must be valid JSON">>)]}}
          end;
        {error, Reason} ->
          {error, {invalid_workflow_dsl, [openagentic_workflow_dsl_utils:err(<<"$">>, <<"read_failed">>, openagentic_workflow_dsl_utils:to_bin(io_lib:format("read failed: ~p", [Reason])))]}}
      end;
    {error, unsafe_path} ->
      {error, {invalid_workflow_dsl, [openagentic_workflow_dsl_utils:err(<<"$">>, <<"unsafe_path">>, <<"workflow path is unsafe">>)]}}
  end.

load_and_validate(ProjectDir0, RelPath0, Opts0) ->
  ProjectDir = openagentic_workflow_dsl_utils:ensure_list(ProjectDir0),
  RelPath = openagentic_workflow_dsl_utils:ensure_list(RelPath0),
  Opts = openagentic_workflow_dsl_utils:ensure_map(Opts0),
  case load(ProjectDir, RelPath, Opts) of
    {ok, Wf} -> validate(ProjectDir, Wf, Opts);
    Err -> Err
  end.

validate(ProjectDir0, Workflow0, Opts0) ->
  ProjectDir = openagentic_workflow_dsl_utils:ensure_list(ProjectDir0),
  Workflow = openagentic_workflow_dsl_utils:ensure_map(Workflow0),
  Opts = openagentic_workflow_dsl_utils:ensure_map(Opts0),
  StrictUnknown = openagentic_workflow_dsl_utils:to_bool_default(maps:get(strict_unknown_fields, Opts, true), true),
  Errors0 = [],
  AllowedTop = [<<"workflow_version">>, <<"name">>, <<"description">>, <<"roles">>, <<"defaults">>, <<"steps">>],
  Errors1 = openagentic_workflow_dsl_utils:maybe_only_keys(StrictUnknown, Workflow, AllowedTop, <<"$">>, Errors0),
  WfVer = openagentic_workflow_dsl_utils:get_bin(Workflow, [<<"workflow_version">>, workflow_version], <<>>),
  Errors2 =
    case WfVer of
      <<"1.0">> -> Errors1;
      <<>> -> [openagentic_workflow_dsl_utils:err(<<"workflow_version">>, <<"missing">>, <<"workflow_version is required">>) | Errors1];
      _ -> [openagentic_workflow_dsl_utils:err(<<"workflow_version">>, <<"unsupported_version">>, iolist_to_binary([<<"unsupported workflow_version: ">>, WfVer])) | Errors1]
    end,
  Name = openagentic_workflow_dsl_utils:get_bin(Workflow, [<<"name">>, name], <<>>),
  Errors3 = openagentic_workflow_dsl_utils:require_nonempty_bin(<<"name">>, Name, <<"name is required">>, Errors2),
  Steps0 = openagentic_workflow_dsl_utils:get_any(Workflow, [<<"steps">>, steps], undefined),
  {Steps, Errors4} = openagentic_workflow_dsl_utils:require_list(<<"steps">>, Steps0, <<"steps must be an array">>, Errors3),
  Errors5 = case Steps of [] -> [openagentic_workflow_dsl_utils:err(<<"steps">>, <<"empty">>, <<"steps must be non-empty">>) | Errors4]; _ -> Errors4 end,
  {StepInfos, Errors6} = openagentic_workflow_dsl_steps:validate_steps(ProjectDir, Steps, StrictUnknown, Errors5),
  StepIds = [Id || #{id := Id} <- StepInfos],
  StepIdSet = maps:from_list([{Id, true} || Id <- StepIds]),
  Errors7 = openagentic_workflow_dsl_transitions:validate_transitions(StepInfos, StepIdSet, Errors6),
  Errors8 = openagentic_workflow_dsl_transitions:validate_terminal_path(StepInfos, StepIdSet, Errors7),
  case openagentic_workflow_dsl_utils:sort_errors(Errors8) of
    [] -> {ok, normalize_workflow(Workflow, StepInfos)};
    ErrorsSorted -> {error, {invalid_workflow_dsl, ErrorsSorted}}
  end.

normalize_workflow(Workflow, StepInfos) ->
  StepsById = maps:from_list([{Id, Raw} || #{id := Id, raw := Raw} <- StepInfos, Id =/= <<>>]),
  Workflow#{
    <<"steps_by_id">> => StepsById,
    <<"start_step_id">> => case StepInfos of [#{id := Id} | _] -> Id; _ -> <<>> end
  }.
