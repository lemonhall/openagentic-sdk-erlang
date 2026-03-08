-module(openagentic_case_store_task_history_versions).
-export([build_latest_version_diff/2, build_historical_version_summary/1, version_changed_fields/2]).

build_latest_version_diff(Versions0, Authorization0) ->
  Versions = [openagentic_case_store_common_core:ensure_map(V) || V <- Versions0],
  Authorization = openagentic_case_store_common_core:ensure_map(Authorization0),
  case lists:reverse(Versions) of
    [Current0, Previous0 | _] ->
      Current = openagentic_case_store_common_core:ensure_map(Current0),
      Previous = openagentic_case_store_common_core:ensure_map(Previous0),
      CurrentSpec = openagentic_case_store_common_core:ensure_map(maps:get(spec, Current, #{})),
      PreviousSpec = openagentic_case_store_common_core:ensure_map(maps:get(spec, Previous, #{})),
      BeforeSlots = openagentic_case_store_task_auth_validation:required_credential_slots(openagentic_case_store_common_lookup:get_in_map(PreviousSpec, [credential_requirements], #{})),
      AfterSlots = openagentic_case_store_task_auth_validation:required_credential_slots(openagentic_case_store_common_lookup:get_in_map(CurrentSpec, [credential_requirements], #{})),
      NewlyRequired = [Slot || Slot <- AfterSlots, not lists:member(Slot, BeforeSlots)],
      RemovedSlots = [Slot || Slot <- BeforeSlots, not lists:member(Slot, AfterSlots)],
      ChangedFields = version_changed_fields(PreviousSpec, CurrentSpec),
      CredentialRequirementsChanged = BeforeSlots =/= AfterSlots,
      ReauthorizationRequired =
        CredentialRequirementsChanged andalso maps:get(status, Authorization, <<"active">>) =/= <<"active">>,
      #{
        from_version_id => openagentic_case_store_common_meta:id_of(Previous),
        to_version_id => openagentic_case_store_common_meta:id_of(Current),
        change_summary => openagentic_case_store_common_lookup:get_in_map(Current, [audit, change_summary], <<>>),
        changed_fields => ChangedFields,
        changed_field_count => length(ChangedFields),
        credential_requirements_changed => CredentialRequirementsChanged,
        newly_required_slots => NewlyRequired,
        removed_required_slots => RemovedSlots,
        reauthorization_required => ReauthorizationRequired,
        authorization_status => maps:get(status, Authorization, <<"active">>)
      };
    _ ->
      #{}
  end.

build_historical_version_summary(Versions0) ->
  Versions = lists:reverse([openagentic_case_store_common_core:ensure_map(Version) || Version <- Versions0]),
  lists:sublist(
    [
      openagentic_case_store_common_meta:compact_map(
        #{
          task_version_id => openagentic_case_store_common_meta:id_of(Version),
          status => openagentic_case_store_common_lookup:get_in_map(Version, [state, status], undefined),
          created_at => openagentic_case_store_common_lookup:get_in_map(Version, [header, created_at], undefined),
          change_summary => openagentic_case_store_common_lookup:get_in_map(Version, [audit, change_summary], undefined),
          revised_by_op_id => openagentic_case_store_common_lookup:get_in_map(Version, [audit, revised_by_op_id], undefined),
          objective => openagentic_case_store_common_lookup:get_in_map(Version, [spec, objective], undefined)
        }
      )
     || Version <- Versions
    ],
    5
  ).

version_changed_fields(PreviousSpec, CurrentSpec) ->
  Fields =
    [
      objective,
      schedule_policy,
      report_contract,
      alert_rules,
      source_strategy,
      tool_profile,
      credential_requirements,
      autonomy_policy,
      promotion_policy
    ],
  lists:foldl(
    fun (Field, Acc) ->
      Prev = maps:get(Field, PreviousSpec, undefined),
      Curr = maps:get(Field, CurrentSpec, undefined),
      case Prev =:= Curr of
        true -> Acc;
        false ->
          [
            openagentic_case_store_common_meta:compact_map(
              #{
                field => atom_to_binary(Field, utf8),
                from => Prev,
                to => Curr
              }
            )
            | Acc
          ]
      end
    end,
    [],
    Fields
  ).
