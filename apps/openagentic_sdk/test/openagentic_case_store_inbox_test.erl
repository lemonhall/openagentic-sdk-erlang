-module(openagentic_case_store_inbox_test).

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

revise_task_rejects_stale_revision_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),

  {ok, Approved} =
    openagentic_case_store:approve_candidate(
      Root,
      #{case_id => CaseId, candidate_id => id_of(Candidate), approved_by_op_id => <<"lemon">>, approval_summary => <<"Approve">>}
    ),
  Task = maps:get(task, Approved),
  TaskId = id_of(Task),
  GovernanceSid = deep_get(Task, [links, governance_session_id]),
  CurrentRevision = deep_get(Task, [header, revision]),

  ?assertMatch(
    {error, {revision_conflict, CurrentRevision}},
    openagentic_case_store:revise_task(
      Root,
      #{
        case_id => CaseId,
        task_id => TaskId,
        governance_session_id => GovernanceSid,
        revised_by_op_id => <<"lemon">>,
        expected_revision => CurrentRevision - 1,
        objective => <<"new objective">>
      }
    )
  ),
  ok.

global_inbox_read_archive_filter_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, _Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),

  {ok, Inbox0} = openagentic_case_store:list_inbox(Root, #{}),
  [Mail0 | _] = Inbox0,
  MailId = id_of(Mail0),
  ?assertEqual(<<"unread">>, deep_get(Mail0, [state, status])),

  {ok, ReadMail} =
    openagentic_case_store:update_mail_state(
      Root,
      #{case_id => CaseId, mail_id => MailId, status => <<"read">>, acted_by_op_id => <<"lemon">>}
    ),
  ?assertEqual(<<"read">>, deep_get(ReadMail, [state, status])),

  {ok, InboxUnread} = openagentic_case_store:list_inbox(Root, #{status => <<"unread">>}),
  ?assertEqual([], InboxUnread),
  {ok, InboxRead} = openagentic_case_store:list_inbox(Root, #{status => <<"read">>}),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= MailId end, InboxRead)),

  {ok, ArchivedMail} =
    openagentic_case_store:update_mail_state(
      Root,
      #{case_id => CaseId, mail_id => MailId, status => <<"archived">>, acted_by_op_id => <<"lemon">>}
    ),
  ?assertEqual(<<"archived">>, deep_get(ArchivedMail, [state, status])),
  {ok, InboxArchived} = openagentic_case_store:list_inbox(Root, #{status => <<"archived">>}),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= MailId end, InboxArchived)),
  ok.

discard_candidate_marks_candidate_discarded_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [_First, Candidate] = maps:get(candidates, Extracted),

  {ok, Discarded} =
    openagentic_case_store:discard_candidate(
      Root,
      #{
        case_id => CaseId,
        candidate_id => id_of(Candidate),
        reason => <<"Out of scope for this case">>,
        acted_by_op_id => <<"lemon">>
      }
    ),

  ?assertEqual(<<"discarded">>, deep_get(Discarded, [state, status])),
  ok.

