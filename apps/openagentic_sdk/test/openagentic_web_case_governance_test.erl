-module(openagentic_web_case_governance_test).

-include_lib("eunit/include/eunit.hrl").

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

task_detail_and_credential_binding_api_test() ->
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
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve pending credentials">>,
          objective => <<"Track diplomatic statement frequency, wording, and topic shifts">>,
          credential_requirements =>
            #{
              required_slots =>
                [
                  #{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}
                ]
            }
        }
      ),
    TaskId = deep_get_bin(maps:get(<<"task">>, Approved), [<<"header">>, <<"id">>]),
    ?assertEqual(<<"awaiting_credentials">>, deep_get_bin(maps:get(<<"task">>, Approved), [<<"state">>, <<"status">>])),

    {200, TaskDetailHtml} =
      http_get_text(
        Base ++ "view/task-detail.html?case_id=" ++ ensure_list(CaseId) ++ "&task_id=" ++ ensure_list(TaskId)
      ),
    ?assert(string:find(TaskDetailHtml, "taskDetailView") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "credentialBindingForm") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "taskVersions") =/= nomatch),

    {200, Detail0} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    ?assertEqual(<<"awaiting_credentials">>, deep_get_bin(Detail0, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(1, length(maps:get(<<"required_slots">>, maps:get(<<"authorization">>, Detail0)))),
    ?assertEqual(0, length(maps:get(<<"credential_bindings">>, Detail0))),

    {201, Bound} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/credential-bindings",
        #{
          slot_name => <<"x_session">>,
          binding_type => <<"cookie">>,
          provider => <<"x">>,
          material_ref => <<"secure://materials/x-session-cookie">>,
          status => <<"validated">>
        }
      ),
    ?assertEqual(<<"ready_to_activate">>, deep_get_bin(Bound, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(1, length(maps:get(<<"credential_bindings">>, Bound))),

    {200, Activated} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/activate",
        #{activated_by_op_id => <<"lemon">>}
      ),
    ?assertEqual(<<"active">>, deep_get_bin(Activated, [<<"task">>, <<"state">>, <<"status">>]))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

task_revision_api_updates_task_detail_versions_test() ->
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
    CaseId = deep_get_bin(maps:get(<<"case">>, Created), [<<"header">>, <<"id">>]),
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve as monitoring task">>,
          objective => <<"Track diplomatic statement frequency and wording shifts">>
        }
      ),
    Task = maps:get(<<"task">>, Approved),
    TaskId = deep_get_bin(Task, [<<"header">>, <<"id">>]),
    GovernanceSid = deep_get_bin(Task, [<<"links">>, <<"governance_session_id">>]),

    {201, Revised} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/revise",
        #{
          governance_session_id => GovernanceSid,
          revised_by_op_id => <<"lemon">>,
          change_summary => <<"Narrow focus to escalation risk">>,
          objective => <<"Track diplomatic statement shifts with emphasis on escalation risk">>
        }
      ),
    NewVersionId = deep_get_bin(maps:get(<<"task_version">>, Revised), [<<"header">>, <<"id">>]),

    {200, Detail} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    Versions = maps:get(<<"versions">>, Detail),
    ?assertEqual(2, length(Versions)),
    ?assertEqual(NewVersionId, deep_get_bin(maps:get(<<"task">>, Detail), [<<"links">>, <<"active_version_id">>])),
    ?assertEqual(<<"superseded">>, deep_get_bin(lists:nth(1, Versions), [<<"state">>, <<"status">>])),
    ?assertEqual(<<"active">>, deep_get_bin(lists:nth(2, Versions), [<<"state">>, <<"status">>])),
    Diff0 = maps:get(<<"latest_version_diff">>, Detail),
    ?assertEqual(<<"Narrow focus to escalation risk">>, maps:get(<<"change_summary">>, Diff0)),
    ?assertEqual(false, maps:get(<<"reauthorization_required">>, Diff0))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

task_detail_api_exposes_reauthorization_hint_after_revision_test() ->
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
    [Candidate | _] = maps:get(<<"candidates">>, Created),
    CandidateId = deep_get_bin(Candidate, [<<"header">>, <<"id">>]),

    {201, Approved} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/candidates/" ++ ensure_list(CandidateId) ++ "/approve",
        #{
          approved_by_op_id => <<"lemon">>,
          approval_summary => <<"Approve as monitoring task">>,
          objective => <<"Track diplomatic statement frequency and wording shifts">>
        }
      ),
    Task = maps:get(<<"task">>, Approved),
    TaskId = deep_get_bin(Task, [<<"header">>, <<"id">>]),
    GovernanceSid = deep_get_bin(Task, [<<"links">>, <<"governance_session_id">>]),

    {201, _Revised} =
      http_post_json(
        Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/revise",
        #{
          governance_session_id => GovernanceSid,
          revised_by_op_id => <<"lemon">>,
          change_summary => <<"Add credential-gated source access">>,
          objective => <<"Track diplomatic statement shifts with credential-gated source access">>,
          credential_requirements =>
            #{
              required_slots =>
                [
                  #{slot_name => <<"x_session">>, binding_type => <<"cookie">>, provider => <<"x">>}
                ]
            }
        }
      ),

    {200, Detail} = http_get_json(Base ++ "api/cases/" ++ ensure_list(CaseId) ++ "/tasks/" ++ ensure_list(TaskId) ++ "/detail"),
    Diff = maps:get(<<"latest_version_diff">>, Detail),
    ?assertEqual(<<"awaiting_credentials">>, deep_get_bin(Detail, [<<"task">>, <<"state">>, <<"status">>])),
    ?assertEqual(true, maps:get(<<"reauthorization_required">>, Diff)),
    ?assertEqual([<<"x_session">>], maps:get(<<"newly_required_slots">>, Diff)),
    ?assertEqual(<<"awaiting_credentials">>, maps:get(<<"authorization_status">>, Diff))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

case_create_api_requires_completed_workflow_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),

    {400, Res} =
      http_post_json(
        Base ++ "api/cases",
        #{
          workflow_session_id => to_bin(Sid),
          title => <<"Iran Situation">>
        }
      ),
    ?assertEqual(<<"workflow session not completed">>, maps:get(<<"error">>, Res))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

case_governance_static_page_test() ->
  Root = tmp_root(),
  Port = pick_port(),
  PrevTrap = process_flag(trap_exit, true),
  ensure_httpc_started(),
  try
    {ok, _} = openagentic_web:start(#{project_dir => Root, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
    Base = ensure_list(openagentic_web:base_url(#{bind => "127.0.0.1", port => Port})),
    {200, Html} = http_get_text(Base ++ "view/cases.html"),
    {200, GovernanceHtml} = http_get_text(Base ++ "view/governance-session.html"),
    {200, TaskDetailHtml} = http_get_text(Base ++ "view/task-detail.html"),
    {200, IndexHtml} = http_get_text(Base),
    ?assert(string:find(Html, "caseCreateForm") =/= nomatch),
    ?assert(string:find(Html, "caseLifecycleNote") =/= nomatch),
    ?assert(string:find(Html, "btnExtractCandidates") =/= nomatch),
    ?assert(string:find(Html, "candidateList") =/= nomatch),
    ?assert(string:find(Html, "/assets/case-governance.js") =/= nomatch),
    ?assert(string:find(GovernanceHtml, "governanceSessionForm") =/= nomatch),
    ?assert(string:find(GovernanceHtml, "governanceRevisionForm") =/= nomatch),
    ?assert(string:find(GovernanceHtml, "/assets/governance-session.js") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "taskDetailView") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "taskVersionDiff") =/= nomatch),
    ?assert(string:find(TaskDetailHtml, "/assets/task-detail.js") =/= nomatch),
    ?assert(string:find(IndexHtml, "/view/cases.html") =/= nomatch),
    ?assert(string:find(IndexHtml, "btnFileCase") =/= nomatch),
    ?assert(contains_codepoints(IndexHtml, [19977, 30465, 20845, 37096])),
    ?assert(contains_codepoints(IndexHtml, [27969, 31243, 22270]))
  after
    reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.

append_round_result(Root, Sid, FinalText) ->
  {ok, _} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:workflow_done(<<"wf_case">>, <<"governance">>, <<"completed">>, FinalText, #{})
    ),
  ok.

reset_web_runtime() ->
  openagentic_web:stop(),
  maybe_kill(whereis(openagentic_web_runtime_keeper)),
  maybe_kill(whereis(openagentic_web_runtime_sup)),
  maybe_kill(whereis(openagentic_workflow_mgr)),
  maybe_kill(whereis(openagentic_web_q)),
  timer:sleep(100),
  ok.

maybe_kill(Pid) when is_pid(Pid) ->
  catch exit(Pid, kill),
  ok;
maybe_kill(_) ->
  ok.

ensure_httpc_started() ->
  _ = inets:start(),
  case inets:start(httpc) of
    {ok, _Pid} -> ok;
    {error, {already_started, _Pid}} -> ok;
    _ -> ok
  end.

http_post_json(Url0, Body0) ->
  Url = ensure_list(Url0),
  Body = openagentic_json:encode_safe(ensure_map(Body0)),
  Headers = [{"content-type", "application/json"}, {"accept", "application/json"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} =
    httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Opts),
  {Status, openagentic_json:decode(RespBody)}.

http_get_json(Url0) ->
  Url = ensure_list(Url0),
  Headers = [{"accept", "application/json"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} = httpc:request(get, {Url, Headers}, HttpOptions, Opts),
  {Status, openagentic_json:decode(RespBody)}.

http_get_text(Url0) ->
  Url = ensure_list(Url0),
  Headers = [{"accept", "text/html"}],
  HttpOptions = [{timeout, 30000}],
  Opts = [{body_format, binary}],
  {ok, {{_Vsn, Status, _Reason}, _RespHeaders, RespBody}} = httpc:request(get, {Url, Headers}, HttpOptions, Opts),
  Text =
    case unicode:characters_to_list(RespBody, utf8) of
      L when is_list(L) -> L;
      _ -> ensure_list(RespBody)
    end,
  {Status, Text}.

contains_codepoints(Text, Codepoints) ->
  string:find(Text, unicode:characters_to_list(Codepoints)) =/= nomatch.

deep_get_bin(Map0, [Key]) -> to_bin(maps:get(Key, Map0));
deep_get_bin(Map0, [Key | Rest]) -> deep_get_bin(maps:get(Key, Map0), Rest).

deep_get_int(Map0, [Key]) -> maps:get(Key, Map0);
deep_get_int(Map0, [Key | Rest]) -> deep_get_int(maps:get(Key, Map0), Rest).

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_web_case_governance_test", Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

pick_port() ->
  case gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}, binary, {active, false}]) of
    {ok, Sock} ->
      {ok, {_Ip, Port}} = inet:sockname(Sock),
      ok = gen_tcp:close(Sock),
      Port;
    _ ->
      18090
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
