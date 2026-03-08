-module(openagentic_case_store_test_support).

-export([create_case_fixture/1, create_active_task_fixture/1, create_active_task_fixture/2, append_round_result/3, id_of/1, deep_get/2, tmp_root/0, ensure_list/1, to_bin/1, file_lines/1]).

create_case_fixture(Root) ->
  {ok, Sid} = openagentic_session_store:create_session(Root, #{}),
  ok =
    append_round_result(
      Root,
      Sid,
      <<"## Suggested Monitoring Items\n",
        "- Monitor Iran diplomatic statement frequency and wording shifts\n",
        "- Track US sanctions policy and enforcement cadence\n">>
    ),
  {ok, Created} =
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
  {id_of(maps:get('case', Created)), id_of(maps:get(round, Created)), Sid}.

create_active_task_fixture(Root) ->
  create_active_task_fixture(Root, #{}).

create_active_task_fixture(Root, ApproveExtras0) ->
  {CaseId, RoundId, _Sid} = create_case_fixture(Root),
  {ok, Extracted} = openagentic_case_store:extract_candidates(Root, #{case_id => CaseId, round_id => RoundId}),
  [Candidate | _] = maps:get(candidates, Extracted),
  CandidateId = id_of(Candidate),
  ApproveExtras =
    maps:merge(
      #{
        case_id => CaseId,
        candidate_id => CandidateId,
        approved_by_op_id => <<"lemon">>,
        approval_summary => <<"approve for monitoring execution">>,
        objective => <<"Track diplomatic statement frequency and wording shifts">>
      },
      ApproveExtras0
    ),
  {ok, Approved} =
    openagentic_case_store:approve_candidate(Root, ApproveExtras),
  {CaseId, id_of(maps:get(task, Approved))}.

append_round_result(Root, Sid, FinalText) ->
  {ok, _} =
    openagentic_session_store:append_event(
      Root,
      Sid,
      openagentic_events:workflow_done(<<"wf_case">>, <<"governance">>, <<"completed">>, FinalText, #{})
    ),
  ok.

id_of(Obj) -> deep_get(Obj, [header, id]).

deep_get(Obj, [Key]) -> maps:get(Key, Obj);
deep_get(Obj, [Key | Rest]) -> deep_get(maps:get(Key, Obj), Rest).

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Cwd, ".tmp", "eunit", "openagentic_case_store_test", Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

file_lines(Path) ->
  {ok, Bin} = file:read_file(Path),
  [Line || Line <- binary:split(Bin, <<"\n">>, [global]), Line =/= <<>>].
