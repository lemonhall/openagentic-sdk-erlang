-module(openagentic_web_runtime_question_broker_test).

-include_lib("eunit/include/eunit.hrl").

web_question_broker_ignores_duplicate_answer_test_() ->
  {timeout, 10, fun web_question_broker_ignores_duplicate_answer_body/0}.

web_question_broker_ignores_duplicate_answer_body() ->
  openagentic_web_runtime_test_support:reset_web_runtime(),
  PrevTrap = process_flag(trap_exit, true),
  try
    {ok, QPid} = openagentic_web_q:start_link(),
    Parent = self(),
    Qid = <<"q_dup_1">>,
    AskPid = spawn(fun () ->
      Answer = openagentic_web_q:ask(<<"wf_1">>, #{question_id => Qid, prompt => <<"Allow?">>, choices => [<<"yes">>, <<"no">>]}),
      Parent ! {ask_answer, Answer}
    end),
    timer:sleep(50),
    ok = openagentic_web_q:answer(Qid, <<"yes">>),
    receive
      {ask_answer, <<"yes">>} -> ok
    after 5000 ->
      ?assert(false)
    end,
    ok = openagentic_web_q:answer(Qid, <<"yes">>),
    timer:sleep(100),
    ?assert(is_process_alive(QPid)),
    ?assert(is_process_alive(AskPid) =:= false)
  after
    openagentic_web_runtime_test_support:reset_web_runtime(),
    process_flag(trap_exit, PrevTrap)
  end,
  ok.
