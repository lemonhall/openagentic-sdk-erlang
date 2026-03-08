-module(openagentic_case_store_template_library_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [
  create_case_fixture/1,
  create_active_task_fixture/1,
  create_active_task_fixture/2,
  append_round_result/3,
  id_of/1,
  deep_get/2,
  tmp_root/0,
  ensure_list/1,
  to_bin/1,
  file_lines/1
]).

template_library_instantiation_and_history_registry_test() ->
  Root = tmp_root(),
  {CaseId, _RoundId, _Sid} = create_case_fixture(Root),

  {ok, CreatedTemplate} =
    openagentic_case_store:create_template(
      Root,
      #{
        case_id => CaseId,
        created_by_op_id => <<"lemon">>,
        title => <<"外交表态监测模板">>,
        summary => <<"适用于外交表态频率、措辞与升级风险监测">>,
        objective => <<"Track diplomatic statement shifts with escalation risk emphasis">>,
        template_body => <<"# Template\n\nReference fetch + parse scaffold\n">>,
        credential_requirements => #{required_slots => [#{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}]} 
      }
    ),
  Template = maps:get(template, CreatedTemplate),
  TemplateId = id_of(Template),

  {ok, Templates} = openagentic_case_store:list_templates(Root, CaseId),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= TemplateId end, Templates)),

  {ok, Instantiated} =
    openagentic_case_store:instantiate_template_candidate(
      Root,
      #{case_id => CaseId, template_id => TemplateId, acted_by_op_id => <<"lemon">>}
    ),
  Candidate = maps:get(candidate, Instantiated),
  ?assertEqual(TemplateId, deep_get(Candidate, [spec, template_ref])),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => id_of(Candidate),
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"Instantiate from template">>
      }
    ),
  Task = maps:get(task, Approved),
  Version = maps:get(task_version, Approved),
  CaseDir = filename:join([Root, "cases", ensure_list(CaseId)]),
  RegistryPath = filename:join([CaseDir, "meta", "object-type-registry.json"]),
  CaseHistoryPath = filename:join([CaseDir, "meta", "history.jsonl"]),
  TaskHistoryPath = filename:join([CaseDir, "meta", "tasks", ensure_list(id_of(Task)), "history.jsonl"]),
  WorkspaceRef = deep_get(Task, [links, workspace_ref]),
  TaskWorkspace = filename:join([CaseDir, ensure_list(WorkspaceRef)]),
  ?assertEqual(TemplateId, deep_get(Task, [spec, template_ref])),
  ?assertEqual(TemplateId, deep_get(Version, [links, derived_from_template_ref])),
  ?assert(filelib:is_file(RegistryPath)),
  ?assert(filelib:is_file(CaseHistoryPath)),
  ?assert(filelib:is_file(TaskHistoryPath)),
  ?assert(length(file_lines(CaseHistoryPath)) > 0),
  ?assert(length(file_lines(TaskHistoryPath)) > 0),
  ?assert(filelib:is_file(filename:join([TaskWorkspace, "TASK.md"]))),
  ok.

