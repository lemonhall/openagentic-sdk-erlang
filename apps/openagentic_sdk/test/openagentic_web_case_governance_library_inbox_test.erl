-module(openagentic_web_case_governance_library_inbox_test).

-include_lib("eunit/include/eunit.hrl").

-import(openagentic_web_case_governance_test_support, [
  append_round_result/3,
  reset_web_runtime/0,
  maybe_kill/1,
  ensure_httpc_started/0,
  http_post_json/2,
  http_get_json/1,
  http_get_text/1,
  contains_codepoints/2,
  deep_get_bin/2,
  deep_get_int/2,
  tmp_root/0,
  pick_port/0,
  ensure_map/1,
  ensure_list/1,
  to_bin/1
]).

template_library_and_global_inbox_api_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    ok =
      append_round_result(
        Root,
        Sid,
        <<"## Suggested Monitoring Items\n",
          "- Monitor Iran diplomatic statement frequency and wording shifts\n",
          "- Track US sanctions policy and enforcement cadence\n">>
      ),
    {ok, _} =
      openagentic_web:start(
        #{
          project_dir => Root,
          session_root => Root,
          web_bind => "127.0.0.1",
          web_port => Port,
          provider_mod => openagentic_testing_provider,
          tools => [openagentic_tool_echo],
          permission_mode_override => bypass,
          api_key => <<"x">>,
          model => <<"x">>
        }
      ),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {201, Created} =
      http_post_json(
        Base ++ "api/cases",
        #{
          workflow_session_id => to_bin(Sid),
          title => <<"Iran Situation">>,
          opening_brief => <<"Create a long-running governance case around Iran">>,
          current_summary => <<"Deliberation completed; waiting for candidate extraction">>
        }
      ),
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Mail0 | _] = maps:get(<<"mail">>, maps:get(<<"overview">>, Created)),
    MailId = deep_get_bin(Mail0, [<<"header">>, <<"id">>]),

    {201, TemplateCreated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/templates",
        #{
          created_by_op_id => <<"lemon">>,
          title => <<"外交表态监测模板">>,
          summary => <<"适用于外交表态频率、措辞与升级风险监测">>,
          objective => <<"Track diplomatic statement shifts with escalation risk emphasis">>,
          template_body => <<"# Template\n\nReference fetch + parse scaffold\n">>
        }
      ),
    TemplateId = deep_get_bin(maps:get(<<"template">>, TemplateCreated), [<<"header">>, <<"id">>]),

    {200, Templates} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/templates"),
    ?assert(lists:any(fun (Item) -> deep_get_bin(Item, [<<"header">>, <<"id">>]) =:= TemplateId end, maps:get(<<"templates">>, Templates))),

    {201, Instantiated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/templates/" ++ ensure_list(TemplateId) ++ "/instantiate",
        #{acted_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(TemplateId, deep_get_bin(maps:get(<<"candidate">>, Instantiated), [<<"spec">>, <<"template_ref">>])),

    {200, Inbox0} = http_get_json(Base ++ "api/inbox?status=unread"),
    ?assert(lists:any(fun (Item) -> deep_get_bin(Item, [<<"header">>, <<"id">>]) =:= MailId end, maps:get(<<"mail">>, Inbox0))),

    {200, Unread0} = http_get_json(Base ++ "api/inbox/unread-count"),
    ?assert(maps:get(<<"unread_count">>, Unread0) >= 1),

    {200, ReadMail} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/mail/" ++ ensure_list(MailId) ++ "/read",
        #{acted_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"read">>, deep_get_bin(ReadMail, [<<"mail">>, <<"state">>, <<"status">>])),

    {200, InboxRead} = http_get_json(Base ++ "api/inbox?status=read"),
    ?assert(lists:any(fun (Item) -> deep_get_bin(Item, [<<"header">>, <<"id">>]) =:= MailId end, maps:get(<<"mail">>, InboxRead))),

    {200, ArchivedMail} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/mail/" ++ ensure_list(MailId) ++ "/archive",
        #{acted_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"archived">>, deep_get_bin(ArchivedMail, [<<"mail">>, <<"state">>, <<"status">>])),

    {200, InboxArchived} = http_get_json(Base ++ "api/inbox?status=archived"),
    ?assert(lists:any(fun (Item) -> deep_get_bin(Item, [<<"header">>, <<"id">>]) =:= MailId end, maps:get(<<"mail">>, InboxArchived)))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

