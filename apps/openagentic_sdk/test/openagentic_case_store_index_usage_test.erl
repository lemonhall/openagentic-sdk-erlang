-module(openagentic_case_store_index_usage_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_case_store_test_support, [
  create_case_fixture/1,
  create_active_task_fixture/1,
  id_of/1,
  tmp_root/0
]).

unread_inbox_uses_mail_unread_index_before_dir_scan_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, _Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "indexes", "mail-unread.json"]))),
  ok = file:write_file(filename:join([CaseDir, "meta", "mail", "poison-unread.json"]), <<"{">>),
  {ok, InboxUnread} = openagentic_case_store:list_inbox(Root, #{case_id => CaseId, status => <<"unread">>}),
  ?assert(length(InboxUnread) >= 2),
  ok.

read_inbox_uses_mail_status_index_before_dir_scan_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, _Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  {ok, Inbox0} = openagentic_case_store:list_inbox(Root, #{case_id => CaseId, status => <<"unread">>}),
  [Mail0 | _] = Inbox0,
  MailId = id_of(Mail0),
  {ok, _ReadMail} =
    openagentic_case_store:update_mail_state(
      Root,
      #{case_id => CaseId, mail_id => MailId, status => <<"read">>, acted_by_op_id => <<"lemon">>}
    ),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  ?assert(filelib:is_file(filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"]))),
  ok = file:write_file(filename:join([CaseDir, "meta", "mail", "poison-read.json"]), <<"{">>),
  {ok, InboxRead} = openagentic_case_store:list_inbox(Root, #{case_id => CaseId, status => <<"read">>}),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= MailId end, InboxRead)),
  ok.

unread_inbox_falls_back_when_mail_indexes_missing_test() ->
  Root = tmp_root(),
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, _Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  _ = file:delete(filename:join([CaseDir, "meta", "indexes", "mail-unread.json"])),
  _ = file:delete(filename:join([CaseDir, "meta", "indexes", "mail-by-status.json"])),
  {ok, InboxUnread} = openagentic_case_store:list_inbox(Root, #{case_id => CaseId, status => <<"unread">>}),
  ?assert(length(InboxUnread) >= 2),
  ok.

overview_uses_indexes_before_dir_scan_test() ->
  Root = tmp_root(),
  {CaseId, TaskId} = create_active_task_fixture(Root),
  CaseDir = openagentic_case_store_repo_paths:case_dir(Root, CaseId),
  PoisonTaskDir = filename:join([CaseDir, "meta", "tasks", "poison"]),
  ok = filelib:ensure_dir(filename:join([PoisonTaskDir, "x"])),
  ok = file:write_file(filename:join([PoisonTaskDir, "task.json"]), <<"{">>),
  ok = file:write_file(filename:join([CaseDir, "meta", "mail", "poison-overview.json"]), <<"{">>),
  ok = file:write_file(filename:join([CaseDir, "meta", "packs", "poison.json"]), <<"{">>),
  ok = file:write_file(filename:join([CaseDir, "meta", "inspection_reviews", "poison.json"]), <<"{">>),
  ok = file:write_file(filename:join([CaseDir, "meta", "reconsideration_packages", "poison.json"]), <<"{">>),
  {ok, Overview} = openagentic_case_store:get_case_overview(Root, CaseId),
  Tasks = maps:get(tasks, Overview),
  ?assert(lists:any(fun (Item) -> id_of(Item) =:= TaskId end, Tasks)),
  ?assert(length(maps:get(mail, Overview)) >= 1),
  ?assertEqual([], maps:get(observation_packs, Overview)),
  ?assertEqual([], maps:get(inspection_reviews, Overview)),
  ?assertEqual([], maps:get(reconsideration_packages, Overview)),
  ok.
