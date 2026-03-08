-module(openagentic_case_store_common_meta).
-export([header/3, display_code/1, new_id/1, id_of/1, default_timezone/1, compact_map/1, initial_task_status/1, task_health_for_status/1, first_defined/1, now_ts/0]).

header(Id, Type, Now) ->
  #{id => Id, type => Type, schema_version => <<"case-governance/v1">>, created_at => Now, updated_at => Now, revision => 1}.

display_code(Prefix) ->
  Suffix = integer_to_binary(erlang:unique_integer([positive, monotonic])),
  <<Prefix/binary, $-, Suffix/binary>>.

new_id(Prefix) ->
  Ts = integer_to_binary(erlang:system_time(microsecond)),
  N = integer_to_binary(erlang:unique_integer([positive, monotonic])),
  <<Prefix/binary, $_, Ts/binary, $_, N/binary>>.

id_of(Obj) -> openagentic_case_store_common_lookup:get_in_map(Obj, [header, id], <<>>).

default_timezone(CaseObj) -> openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, default_timezone], <<"Asia/Shanghai">>).

compact_map(Map) -> maps:filter(fun (_K, V) -> V =/= undefined end, openagentic_case_store_common_core:ensure_map(Map)).

initial_task_status(CredentialRequirements) ->
  case openagentic_case_store_task_auth_validation:required_credential_slots(CredentialRequirements) of
    [] -> <<"active">>;
    _ -> <<"awaiting_credentials">>
  end.

task_health_for_status(<<"active">>) -> <<"ok">>;
task_health_for_status(<<"ready_to_activate">>) -> <<"pending_activation">>;
task_health_for_status(<<"awaiting_credentials">>) -> <<"authorization_pending">>;
task_health_for_status(<<"credential_expired">>) -> <<"credential_expired">>;
task_health_for_status(<<"reauthorization_required">>) -> <<"reauthorization_required">>;
task_health_for_status(_) -> <<"ok">>.

first_defined([]) -> undefined;
first_defined([undefined | Rest]) -> first_defined(Rest);
first_defined([Value | _]) -> Value.

now_ts() -> erlang:system_time(millisecond) / 1000.0.
