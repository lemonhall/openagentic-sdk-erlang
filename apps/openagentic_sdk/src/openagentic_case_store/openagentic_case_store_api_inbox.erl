-module(openagentic_case_store_api_inbox).
-export([list_inbox/2, update_mail_state/2]).

list_inbox(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  StatusFilter = openagentic_case_store_common_lookup:get_bin(Input, [status], undefined),
  CaseFilter = openagentic_case_store_common_lookup:get_bin(Input, [case_id, caseId], undefined),
  CasesRoot = filename:join([RootDir, "cases"]),
  Mail0 =
    lists:foldl(
      fun (CaseName, Acc) ->
        CaseId = openagentic_case_store_common_core:to_bin(CaseName),
        case CaseFilter =:= undefined orelse CaseFilter =:= CaseId of
          false -> Acc;
          true ->
            CaseDir = openagentic_case_store_repo_paths:case_dir(RootDir, CaseId),
            case filelib:is_file(openagentic_case_store_repo_paths:case_file(CaseDir)) of
              false -> Acc;
              true ->
                CaseObj = openagentic_case_store_repo_persist:read_json(openagentic_case_store_repo_paths:case_file(CaseDir)),
                MailItems =
                  [
                    openagentic_case_store_mail:decorate_global_mail(Item, CaseObj)
                   || Item <- openagentic_case_store_repo_readers:read_mail_objects_indexed(CaseDir, StatusFilter)
                  ],
                Acc ++ MailItems
            end
        end
      end,
      [],
      openagentic_case_store_repo_readers:safe_list_dir(CasesRoot)
    ),
  Mail1 =
    case StatusFilter of
      undefined -> Mail0;
      <<"all">> -> Mail0;
      _ -> [Item || Item <- Mail0, openagentic_case_store_common_lookup:get_in_map(Item, [state, status], <<>>) =:= StatusFilter]
    end,
  {ok, lists:reverse(openagentic_case_store_repo_readers:sort_by_created_at(Mail1))}.

update_mail_state(RootDir0, Input0) ->
  RootDir = openagentic_case_store_common_core:ensure_list(RootDir0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  CaseId = openagentic_case_store_common_lookup:required_bin(Input, [case_id, caseId]),
  MailId = openagentic_case_store_common_lookup:required_bin(Input, [mail_id, mailId]),
  Status = openagentic_case_store_common_lookup:required_bin(Input, [status]),
  case openagentic_case_store_repo_readers:load_case(RootDir, CaseId) of
    {error, Reason} -> {error, Reason};
    {ok, _CaseObj, CaseDir} ->
      MailPath = openagentic_case_store_repo_paths:mail_file(CaseDir, MailId),
      case filelib:is_file(MailPath) of
        false -> {error, not_found};
        true ->
          Mail0 = openagentic_case_store_repo_persist:read_json(MailPath),
          case openagentic_case_store_task_auth_validation:maybe_check_expected_revision(Input, Mail0) of
            ok ->
              Now = openagentic_case_store_common_meta:now_ts(),
              Mail1 = openagentic_case_store_mail:update_mail_status(Mail0, Input, Status, Now),
              ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, MailPath, Mail1),
              ok = openagentic_case_store_case_state:rebuild_indexes(RootDir, CaseId),
              {ok, Mail1};
            {error, Reason} -> {error, Reason}
          end
      end
  end.
