-module(openagentic_case_store).
-export([create_case_from_round/2, extract_candidates/2, approve_candidate/2, discard_candidate/2, get_case_overview/2, list_templates/2, create_template/2, instantiate_template_candidate/2, list_inbox/2, update_mail_state/2, get_task_detail/3, revise_task/2, upsert_credential_binding/2, invalidate_credential_binding/2, activate_task/2, run_task/2, retry_run/2, create_observation_pack/2, inspect_observation_pack/2, create_reconsideration_package/2, get_reconsideration_preview/3, defer_reconsideration_package/2, start_reconsideration/2]).

create_case_from_round(RootDir, Input) -> openagentic_case_store_api_case_create:create_case_from_round(RootDir, Input).
extract_candidates(RootDir, Input) -> openagentic_case_store_api_candidate_flow:extract_candidates(RootDir, Input).
approve_candidate(RootDir, Input) -> openagentic_case_store_api_candidate_approve:approve_candidate(RootDir, Input).
discard_candidate(RootDir, Input) -> openagentic_case_store_api_candidate_flow:discard_candidate(RootDir, Input).
get_case_overview(RootDir, CaseId) -> openagentic_case_store_api_candidate_flow:get_case_overview(RootDir, CaseId).
list_templates(RootDir, CaseId) -> openagentic_case_store_api_candidate_flow:list_templates(RootDir, CaseId).
create_template(RootDir, Input) -> openagentic_case_store_api_templates:create_template(RootDir, Input).
instantiate_template_candidate(RootDir, Input) -> openagentic_case_store_api_templates:instantiate_template_candidate(RootDir, Input).
list_inbox(RootDir, Input) -> openagentic_case_store_api_inbox:list_inbox(RootDir, Input).
update_mail_state(RootDir, Input) -> openagentic_case_store_api_inbox:update_mail_state(RootDir, Input).
get_task_detail(RootDir, CaseId, TaskId) -> openagentic_case_store_api_task_detail:get_task_detail(RootDir, CaseId, TaskId).
revise_task(RootDir, Input) -> openagentic_case_store_api_task_revise:revise_task(RootDir, Input).
upsert_credential_binding(RootDir, Input) -> openagentic_case_store_api_task_bindings_upsert:upsert_credential_binding(RootDir, Input).
invalidate_credential_binding(RootDir, Input) -> openagentic_case_store_api_task_bindings_invalidate:invalidate_credential_binding(RootDir, Input).
activate_task(RootDir, Input) -> openagentic_case_store_api_task_activate:activate_task(RootDir, Input).
run_task(RootDir, Input) -> openagentic_case_store_api_task_run:run_task(RootDir, Input).
retry_run(RootDir, Input) -> openagentic_case_store_api_task_run:retry_run(RootDir, Input).
create_observation_pack(RootDir, Input) -> openagentic_case_store_api_reconsideration:create_observation_pack(RootDir, Input).
inspect_observation_pack(RootDir, Input) -> openagentic_case_store_api_reconsideration:inspect_observation_pack(RootDir, Input).
create_reconsideration_package(RootDir, Input) -> openagentic_case_store_api_reconsideration:create_reconsideration_package(RootDir, Input).
get_reconsideration_preview(RootDir, CaseId, PackageId) -> openagentic_case_store_api_reconsideration:get_reconsideration_preview(RootDir, CaseId, PackageId).
defer_reconsideration_package(RootDir, Input) -> openagentic_case_store_api_reconsideration:defer_reconsideration_package(RootDir, Input).
start_reconsideration(RootDir, Input) -> openagentic_case_store_api_reconsideration:start_reconsideration(RootDir, Input).
