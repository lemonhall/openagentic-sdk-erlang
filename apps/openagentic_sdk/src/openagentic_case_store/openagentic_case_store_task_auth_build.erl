-module(openagentic_case_store_task_auth_build).
-export([build_credential_binding/6, update_credential_binding/4]).

build_credential_binding(CaseId, TaskId, BindingId, Input, SlotName, Now) ->
  #{
    header => openagentic_case_store_common_meta:header(BindingId, <<"credential_binding">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, task_id => TaskId}),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          slot_name => SlotName,
          binding_type => openagentic_case_store_common_lookup:get_bin(Input, [binding_type, bindingType], undefined),
          provider => openagentic_case_store_common_lookup:get_bin(Input, [provider], undefined),
          material_ref => openagentic_case_store_common_lookup:get_bin(Input, [material_ref, materialRef], undefined)
        }
      ),
    state =>
      openagentic_case_store_common_meta:compact_map(
        #{
          status => openagentic_case_store_common_lookup:get_bin(Input, [status], <<"validated">>),
          validated_at => openagentic_case_store_task_auth_resolve:resolve_validated_at(Input, Now),
          expires_at => openagentic_case_store_common_lookup:get_number(Input, [expires_at, expiresAt], undefined)
        }
      ),
    audit =>
      openagentic_case_store_common_meta:compact_map(
        #{
          created_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
          note => openagentic_case_store_common_lookup:get_bin(Input, [note], undefined)
        }
      ),
    ext => #{}
  }.

update_credential_binding(Binding0, Input, SlotName, Now) ->
  openagentic_case_store_repo_persist:update_object(
    Binding0,
    Now,
    fun (Obj) ->
      Obj#{
        spec =>
          maps:merge(
            maps:get(spec, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(
              #{
                slot_name => SlotName,
                binding_type => openagentic_case_store_common_lookup:get_bin(Input, [binding_type, bindingType], openagentic_case_store_common_lookup:get_in_map(Obj, [spec, binding_type], undefined)),
                provider => openagentic_case_store_common_lookup:get_bin(Input, [provider], openagentic_case_store_common_lookup:get_in_map(Obj, [spec, provider], undefined)),
                material_ref => openagentic_case_store_common_lookup:get_bin(Input, [material_ref, materialRef], openagentic_case_store_common_lookup:get_in_map(Obj, [spec, material_ref], undefined))
              }
            )
          ),
        state =>
          maps:merge(
            maps:get(state, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(
              #{
                status => openagentic_case_store_common_lookup:get_bin(Input, [status], openagentic_case_store_common_lookup:get_in_map(Obj, [state, status], <<"validated">>)),
                validated_at => openagentic_case_store_task_auth_resolve:resolve_validated_at(Input, Now, Obj),
                expires_at => openagentic_case_store_common_lookup:get_number(Input, [expires_at, expiresAt], openagentic_case_store_common_lookup:get_in_map(Obj, [state, expires_at], undefined))
              }
            )
          ),
        audit =>
          maps:merge(
            maps:get(audit, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(
              #{
                updated_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined),
                note => openagentic_case_store_common_lookup:get_bin(Input, [note], undefined)
              }
            )
          )
      }
    end
  ).
