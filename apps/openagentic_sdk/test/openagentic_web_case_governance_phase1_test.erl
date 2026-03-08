-module(openagentic_web_case_governance_phase1_test).

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

phase1_case_governance_api_test() ->
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
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
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
    CaseObj = maps:get(<<"case">>, Created),
    RoundObj = maps:get(<<"round">>, Created),
    CaseId = deep_get_bin(CaseObj, [<<"header">>, <<"id">>]),
    RoundId = deep_get_bin(RoundObj, [<<"header">>, <<"id">>]),

    Candidates = maps:get(<<"candidates">>, Created),
    ?assertEqual(2, length(Candidates)),
    [Candidate1, Candidate2] = Candidates,
    CandidateId1 = deep_get_bin(Candidate1, [<<"header">>, <<"id">>]),
    CandidateId2 = deep_get_bin(Candidate2, [<<"header">>, <<"id">>]),
    ?assertEqual(RoundId, deep_get_bin(Candidate1, [<<"links">>, <<"source_round_id">>])),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId1) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve as monitoring task">>,
          objective => <<"Track diplomatic statement frequency, wording, and topic shifts">>,
          schedule_policy => #{mode => <<"interval">>, interval => #{value => 6, unit => <<"hours">>}},
          report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}
        }
      ),
    ?assertEqual(<<"active">>, deep_get_bin(maps:get(<<"task">>, Approved), [<<"state">>, <<"status">>])),

    {200, Discarded} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId2) ++ "/discard",
        #{reason => <<"Out of scope for this case">>, acted_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"discarded">>, deep_get_bin(maps:get(<<"candidate">>, Discarded), [<<"state">>, <<"status">>])),

    {200, Overview} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/overview"),
    ?assertEqual(1, deep_get_int(Overview, [<<"case">>, <<"state">>, <<"active_task_count">>])),
    ?assertEqual(2, length(maps:get(<<"candidates">>, Overview))),
    ?assertEqual(1, length(maps:get(<<"tasks">>, Overview)))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

