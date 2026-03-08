-module(openagentic_case_store_case_support).
-export([ensure_workflow_session_completed/2, latest_workflow_done_event/1, default_schedule_policy/1, default_report_contract/0, seed_task_workspace/3, seed_template_workspace/3]).

ensure_workflow_session_completed(RootDir, WorkflowSessionId0) ->
  WorkflowSessionId = openagentic_case_store_common_core:ensure_list(WorkflowSessionId0),
  Events = openagentic_session_store:read_events(RootDir, WorkflowSessionId),
  case latest_workflow_done_event(Events) of
    undefined -> throw({error, workflow_session_not_completed});
    Event ->
      case openagentic_case_store_common_lookup:get_bin(Event, [status], <<>>) of
        <<"completed">> -> ok;
        _ -> throw({error, workflow_session_not_completed})
      end
  end.

latest_workflow_done_event(Events) ->
  lists:foldl(
    fun (Event0, Acc0) ->
      Event = openagentic_case_store_common_core:ensure_map(Event0),
      case openagentic_case_store_common_lookup:get_bin(Event, [type], <<>>) of
        <<"workflow.done">> -> Event;
        _ -> Acc0
      end
    end,
    undefined,
    Events
  ).

default_schedule_policy(Timezone) ->
  #{mode => <<"manual">>, timezone => Timezone}.

default_report_contract() ->
  #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}.

seed_task_workspace(TaskWorkspaceDir, CandidateObj, Input) ->
  Title = openagentic_case_store_common_lookup:get_bin(Input, [title], openagentic_case_store_common_lookup:get_in_map(CandidateObj, [spec, title], <<"Untitled Task">>)),
  Objective = openagentic_case_store_common_lookup:get_bin(Input, [objective], openagentic_case_store_common_lookup:get_in_map(CandidateObj, [spec, objective], <<>>)),
  Body =
    iolist_to_binary(
      [
        <<"# ">>, Title, <<"\n\n">>,
        <<"## Mission\n">>, openagentic_case_store_common_lookup:get_in_map(CandidateObj, [spec, mission_statement], Objective), <<"\n\n">>,
        <<"## Objective\n">>, Objective, <<"\n">>
      ]
    ),
  file:write_file(filename:join([TaskWorkspaceDir, "TASK.md"]), Body).

seed_template_workspace(TemplateWorkspaceDir, Input, CaseObj) ->
  Title = openagentic_case_store_common_lookup:get_bin(Input, [title], <<"Untitled Template">>),
  Objective = openagentic_case_store_common_lookup:get_bin(Input, [objective], <<>>),
  Summary = openagentic_case_store_common_lookup:get_bin(Input, [summary], <<>>),
  TemplateBody = openagentic_case_store_common_lookup:get_bin(Input, [template_body, templateBody], undefined),
  Body =
    case TemplateBody of
      undefined ->
        iolist_to_binary(
          [
            <<"# ">>, Title, <<"\n\n">>,
            <<"## Summary\n">>, Summary, <<"\n\n">>,
            <<"## Objective\n">>, Objective, <<"\n\n">>,
            <<"## Timezone\n">>, openagentic_case_store_common_meta:default_timezone(CaseObj), <<"\n">>
          ]
        );
      Value -> Value
    end,
  file:write_file(filename:join([TemplateWorkspaceDir, "TEMPLATE.md"]), Body).
