-module(openagentic_case_store_candidates_build).
-export([create_candidates_and_mail/7, build_candidate/7, build_candidate_mail/6]).

create_candidates_and_mail(_RootDir, _CaseDir, _CaseId, _RoundId, _WorkflowSessionId, [], _Now) -> {[], []};
create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, [Spec | Rest], Now) ->
  CandidateId = openagentic_case_store_common_meta:new_id(<<"candidate">>),
  {ok, ReviewSessionId0} =
    openagentic_session_store:create_session(
      RootDir,
      #{kind => <<"candidate_review">>, case_id => CaseId, round_id => RoundId, candidate_id => CandidateId}
    ),
  ReviewSessionId = openagentic_case_store_common_core:to_bin(ReviewSessionId0),
  CandidateObj = build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, Spec, Now),
  MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
  MailObj = build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:candidate_file(CaseDir, CandidateId), CandidateObj),
  ok = openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:mail_file(CaseDir, MailId), MailObj),
  {RestCandidates, RestMail} = create_candidates_and_mail(RootDir, CaseDir, CaseId, RoundId, WorkflowSessionId, Rest, Now),
  {[CandidateObj | RestCandidates], [MailObj | RestMail]}.

build_candidate(CaseId, RoundId, WorkflowSessionId, CandidateId, ReviewSessionId, Spec0, Now) ->
  Spec = openagentic_case_store_common_core:ensure_map(Spec0),
  #{
    header => openagentic_case_store_common_meta:header(CandidateId, <<"monitoring_candidate">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          source_round_id => RoundId,
          review_session_id => ReviewSessionId,
          approved_task_id => undefined
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          title => openagentic_case_store_common_lookup:get_bin(Spec, [title], <<"Untitled Candidate">>),
          display_code => openagentic_case_store_common_lookup:get_bin(Spec, [display_code, displayCode], openagentic_case_store_common_meta:display_code(<<"CAND">>)),
          mission_statement => openagentic_case_store_common_lookup:get_bin(Spec, [mission_statement, missionStatement], openagentic_case_store_common_lookup:get_bin(Spec, [objective], <<>>)),
          objective => openagentic_case_store_common_lookup:get_bin(Spec, [objective], openagentic_case_store_common_lookup:get_bin(Spec, [mission_statement, missionStatement], <<>>)),
          default_timezone => openagentic_case_store_common_lookup:get_bin(Spec, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>),
          schedule_policy => openagentic_case_store_common_lookup:choose_map(Spec, [schedule_policy, schedulePolicy], openagentic_case_store_case_support:default_schedule_policy(openagentic_case_store_common_lookup:get_bin(Spec, [default_timezone, defaultTimezone], <<"Asia/Shanghai">>))),
          report_contract => openagentic_case_store_common_lookup:choose_map(Spec, [report_contract, reportContract], openagentic_case_store_case_support:default_report_contract()),
          alert_rules => openagentic_case_store_common_lookup:choose_map(Spec, [alert_rules, alertRules], #{}),
          source_strategy => openagentic_case_store_common_lookup:choose_map(Spec, [source_strategy, sourceStrategy], #{}),
          tool_profile => openagentic_case_store_common_lookup:choose_map(Spec, [tool_profile, toolProfile], #{}),
          credential_requirements => openagentic_case_store_common_lookup:choose_map(Spec, [credential_requirements, credentialRequirements], #{}),
          autonomy_policy => openagentic_case_store_common_lookup:choose_map(Spec, [autonomy_policy, autonomyPolicy], #{}),
          promotion_policy => openagentic_case_store_common_lookup:choose_map(Spec, [promotion_policy, promotionPolicy], #{}),
          template_ref => openagentic_case_store_common_lookup:get_bin(Spec, [template_ref, templateRef], undefined),
          extracted_summary => openagentic_case_store_common_lookup:get_bin(Spec, [extracted_summary, extractedSummary], undefined)
        }
      ),
    state => #{status => <<"inbox_pending">>, extracted_at => Now},
    audit =>
      openagentic_case_store_common_meta:compact_map(
        #{
          extracted_from_session_id => WorkflowSessionId,
          extracted_by_role => <<"proposer">>,
          extracted_at => Now
        }
      ),
    ext => #{}
  }.

build_candidate_mail(CaseId, WorkflowSessionId, CandidateId, MailId, CandidateObj, Now) ->
  Title = openagentic_case_store_common_lookup:get_in_map(CandidateObj, [spec, title], <<"Untitled Candidate">>),
  #{
    header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          related_object_refs => [#{type => <<"monitoring_candidate">>, id => CandidateId}],
          source_op_id => undefined,
          source_session_id => WorkflowSessionId
        }
      ),
    spec =>
      #{
        message_type => <<"candidate_review_required">>,
        title => <<"candidate review pending">>,
        summary => Title,
        recommended_action => <<"review_candidate">>,
        available_actions => [<<"approve">>, <<"discard">>]
      },
    state => #{status => <<"unread">>, severity => <<"normal">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"proposer">>},
    ext => #{}
  }.
