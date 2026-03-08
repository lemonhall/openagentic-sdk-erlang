-module(openagentic_web_case_governance_session_query_test).

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

governance_session_page_and_query_api_test() ->
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
    CaseObj = maps:get(<<"case">>, Created),
    CaseId = deep_get_bin(CaseObj, [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),
    ReviewSid = deep_get_bin(Candidate, [<<"links">>, <<"review_session_id">>]),

    {200, GovernanceHtml} =
      http_get_text(
        Base ++
          "view/governance-session.html?sid=" ++ ensure_list(ReviewSid) ++ "&case_id=" ++ ensure_list(CaseId)
      ),
    ?assert(string:find(GovernanceHtml, "governanceSessionForm") =/= nomatch),
    ?assert(string:find(GovernanceHtml, "governanceTranscript") =/= nomatch),

    {200, QueryResp1} =
      http_post_json(
        Base ++ "api/sessions/" ++ ensure_list(ReviewSid) ++ "/query",
        #{message => <<"Please restate the current review focus.">>}
      ),
    ?assertEqual(ReviewSid, maps:get(<<"session_id">>, QueryResp1)),
    ?assertEqual(<<"OK">>, maps:get(<<"final_text">>, QueryResp1)),
    ?assertEqual(
      <<"/api/sessions/", ReviewSid/binary, "/events">>,
      maps:get(<<"events_url">>, QueryResp1)
    ),

    ReviewEvents = openagentic_session_store:read_events(Root, ensure_list(ReviewSid)),
    ?assert(lists:any(fun (Ev) -> maps:get(<<"type">>, Ev, <<>>) =:= <<"user.message">> end, ReviewEvents)),
    ?assert(lists:any(fun (Ev) -> maps:get(<<"type">>, Ev, <<>>) =:= <<"assistant.message">> end, ReviewEvents)),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve as monitoring task">>,
          objective => <<"Track diplomatic statement frequency, wording, and topic shifts">>,
          schedule_policy => #{mode => <<"interval">>, interval => #{value => 6, unit => <<"hours">>}},
          report_contract => #{kind => <<"markdown">>, required_sections => [<<"Summary">>, <<"Facts">>]}
        }
      ),
    GovernanceSid = deep_get_bin(maps:get(<<"task">>, Approved), [<<"links">>, <<"governance_session_id">>]),
    ?assertEqual(ReviewSid, GovernanceSid),

    {200, QueryResp2} =
      http_post_json(
        Base ++ "api/sessions/" ++ ensure_list(GovernanceSid) ++ "/query",
        #{message => <<"Continue governance on the same task.">>}
      ),
    ?assertEqual(GovernanceSid, maps:get(<<"session_id">>, QueryResp2)),
    ?assertEqual(<<"OK">>, maps:get(<<"final_text">>, QueryResp2)),

    {201, Revised} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(deep_get_bin(maps:get(<<"task">>, Approved), [<<"header">>, <<"id">>])) ++ "/revise",
        #{
          governance_session_id => GovernanceSid,
          revised_by_op_id => <<"lemon">>,
          change_summary => <<"Narrow focus to escalation risk">>,
          objective => <<"Track diplomatic statement shifts with emphasis on escalation risk">>
        }
      ),
    RevisedVersion = maps:get(<<"task_version">>, Revised),
    ?assertEqual(<<"active">>, deep_get_bin(RevisedVersion, [<<"state">>, <<"status">>])),

    ReviewEvents2 = openagentic_session_store:read_events(Root, ensure_list(GovernanceSid)),
    ?assert(
      lists:any(
        fun (Ev) -> maps:get(<<"type">>, Ev, <<>>) =:= <<"governance.task_version.created">> end,
        ReviewEvents2
      )
    )
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

