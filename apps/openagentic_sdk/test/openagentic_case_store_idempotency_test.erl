-module(openagentic_case_store_idempotency_test).
-include_lib("eunit/include/eunit.hrl").

approve_candidate_second_time_returns_already_approved_test() ->
  Root = tmp_root(),
  {CaseId, RoundId} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),
  CandidateId = id_of(Candidate),
  Approve = #{case_id => CaseId, candidate_id => CandidateId, approved_by_op_id => <<"lemon">>, approval_summary => <<"approve for execution">>, objective => <<"Track diplomatic wording shifts">>},
  {ok, _} = openagentic_case_store:approve_candidate(Root, Approve),
  ?assertEqual({error, already_approved}, openagentic_case_store:approve_candidate(Root, Approve)),
  ok.

create_case_fixture(Root) ->
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok = append_round_result(Root, Sid),
  {ok, Created} = openagentic_case_store:create_case_from_round(Root, #{workflow_session_id => to_bin(Sid), title => <<"Iran Situation">>, opening_brief => <<"Create a long-running governance case around Iran">>, current_summary => <<"Deliberation completed; waiting for candidate extraction">>}),
  {id_of(maps:get('case', Created)), id_of(maps:get(round, Created))}.

append_round_result(Root, Sid) ->
  {ok, _} = openagentic_session_store:append_event(Root, Sid, openagentic_events:workflow_done(<<"wf_case">>, <<"governance">>, <<"completed">>, <<"## Suggested Monitoring Items
- Monitor Iran diplomatic statement frequency and wording shifts
- Track US sanctions policy and enforcement cadence
">>, #{})),
  ok.

id_of(Obj) -> maps:get(id, maps:get(header, Obj)).

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_case_store_idempotency_test", Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
