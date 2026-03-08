-module(openagentic_case_store_mail).
-export([decorate_global_mail/2, update_mail_status/4, mark_candidate_mail_acted/5, mail_targets_candidate/2]).

decorate_global_mail(Mail0, CaseObj) ->
  Mail = openagentic_case_store_common_core:ensure_map(Mail0),
  Ext0 = openagentic_case_store_common_core:ensure_map(maps:get(ext, Mail, #{})),
  Mail#{
    ext =>
      maps:merge(
        Ext0,
        openagentic_case_store_common_meta:compact_map(
          #{
            case_title => openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, title], undefined),
            case_display_code => openagentic_case_store_common_lookup:get_in_map(CaseObj, [spec, display_code], undefined)
          }
        )
      )
  }.

update_mail_status(Mail0, Input0, Status, Now) ->
  Mail = openagentic_case_store_common_core:ensure_map(Mail0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  openagentic_case_store_repo_persist:update_object(
    Mail,
    Now,
    fun (Obj) ->
      Obj#{
        state =>
          maps:merge(
            maps:get(state, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(
              #{
                status => Status,
                acted_at => Now,
                consumed_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined)
              }
            )
          ),
        audit =>
          maps:merge(
            maps:get(audit, Obj, #{}),
            openagentic_case_store_common_meta:compact_map(#{updated_by_op_id => openagentic_case_store_common_lookup:get_bin(Input, [acted_by_op_id, actedByOpId], undefined)})
          )
      }
    end
  ).

mark_candidate_mail_acted(CaseDir, CandidateId, Action, Actor, Now) ->
  MailDir = filename:join([CaseDir, "meta", "mail"]),
  Paths = openagentic_case_store_repo_readers:json_files(MailDir),
  lists:foreach(
    fun (Path) ->
      Mail0 = openagentic_case_store_repo_persist:read_json(Path),
      case mail_targets_candidate(Mail0, CandidateId) of
        true ->
          Mail1 =
            openagentic_case_store_repo_persist:update_object(
              Mail0,
              Now,
              fun (Obj) ->
                Obj#{
                  state =>
                    maps:merge(
                      maps:get(state, Obj, #{}),
                      openagentic_case_store_common_meta:compact_map(
                        #{status => <<"acted">>, acted_at => Now, acted_action => Action, consumed_by_op_id => Actor}
                      )
                    )
                }
              end
            ),
          ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, Path, Mail1);
        false -> ok
      end
    end,
    Paths
  ),
  ok.

mail_targets_candidate(MailObj, CandidateId) ->
  Refs = openagentic_case_store_common_lookup:get_in_map(MailObj, [links, related_object_refs], []),
  lists:any(
    fun (Ref0) ->
      Ref = openagentic_case_store_common_core:ensure_map(Ref0),
      openagentic_case_store_common_lookup:get_bin(Ref, [type], <<>>) =:= <<"monitoring_candidate">> andalso openagentic_case_store_common_lookup:get_bin(Ref, [id], <<>>) =:= CandidateId
    end,
    openagentic_case_store_common_core:ensure_list_of_maps(Refs)
  ).
