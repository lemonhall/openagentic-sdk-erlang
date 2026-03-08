-module(openagentic_case_store_case_create_test).

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

create_case_from_round_persists_case_and_round_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok = append_round_result(Root, Sid, <<"## Deliberation Summary\n- Keep watching the regional situation\n">>),

  {ok, Res} =
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>,
        opening_brief => <<"Create a long-running governance case around Iran">>,
        current_summary => <<"Deliberation completed; waiting for candidate extraction">>,
        topic => <<"geopolitics">>,
        owner => <<"lemon">>,
        default_timezone => <<"Asia/Shanghai">>
      }
    ),

  CaseObj = maps:get('case', Res),
  RoundObj = maps:get(round, Res),
  CaseId = id_of(CaseObj),
  RoundId = id_of(RoundObj),
  CaseDir = filename:join([Root, "cases", ensure_list(CaseId)]),

  ?assert(filelib:is_dir(filename:join([CaseDir, "meta"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "artifacts"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "workspaces"]))),
  ?assert(filelib:is_dir(filename:join([CaseDir, "published"]))),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "case.json"]))),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "rounds", ensure_list(<<RoundId/binary, ".json">>)]))),
  ?assertEqual(to_bin(Sid), deep_get(CaseObj, [links, origin_workflow_session_id])),
  ?assertEqual(to_bin(Sid), deep_get(RoundObj, [links, workflow_session_id])),
  ok.

create_case_from_round_requires_completed_workflow_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),

  ?assertEqual(
    {error, workflow_session_not_completed},
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>
      }
    )
  ),
  ok.

create_case_from_round_auto_extracts_candidates_by_default_test() ->
  Root = tmp_root(),
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok =
    append_round_result(
      Root,
      Sid,
      <<"## Suggested Monitoring Items\n",
        "- Monitor Iran diplomatic statement frequency and wording shifts\n",
        "- Track US sanctions policy and enforcement cadence\n">>
    ),

  {ok, Res} =
    openagentic_case_store:create_case_from_round(
      Root,
      #{
        workflow_session_id => to_bin(Sid),
        title => <<"Iran Situation">>,
        opening_brief => <<"Create a long-running governance case around Iran">>,
        current_summary => <<"Deliberation completed; waiting for candidate extraction">>
      }
    ),

  Candidates = maps:get(candidates, Res),
  Mail = maps:get(mail, Res),
  Overview = maps:get(overview, Res),
  OverviewCase = maps:get('case', Overview),
  ?assertEqual(2, length(Candidates)),
  ?assertEqual(2, length(Mail)),
  ?assertEqual(<<"post_deliberation_extraction">>, deep_get(OverviewCase, [state, phase])),
  ok.

extract_candidates_from_round_creates_inbox_candidates_and_mail_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),

  {ok, Res} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),

  Candidates = maps:get(candidates, Res),
  Mail = maps:get(mail, Res),
  ?assertEqual(2, length(Candidates)),
  ?assertEqual(2, length(Mail)),
  lists:foreach(
    fun (Candidate) ->
      ReviewSid = deep_get(Candidate, [links, review_session_id]),
      ?assertEqual(<<"inbox_pending">>, deep_get(Candidate, [state, status])),
      ?assert(byte_size(ReviewSid) > 0),
      ?assert(filelib:is_dir(openagentic_session_store:session_dir(Root, ensure_list(ReviewSid))))
    end,
    Candidates
  ),
  ok.

