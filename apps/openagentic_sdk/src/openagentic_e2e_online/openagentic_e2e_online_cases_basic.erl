-module(openagentic_e2e_online_cases_basic).
-export([cases/2]).

cases(Cfg, TmpProject) ->
  [
    case_basic_pong(Cfg, TmpProject),
    case_streaming_deltas(Cfg, TmpProject),
    case_session_resume(Cfg, TmpProject),
    case_tools_responses_best_effort(Cfg, TmpProject),
    case_tools_list_read_grep_glob(Cfg, TmpProject)
  ].

case_basic_pong(Cfg, TmpProject) ->
  Prompt = <<"Reply with exactly: pong">>,
  Opts = openagentic_e2e_online_query:base_runtime_opts(Cfg, TmpProject, #{include_partial_messages => false, tools => []}),
  {Res, _Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:assert_ok_text_contains(basic_pong, Res, <<"pong">>).

case_streaming_deltas(Cfg, TmpProject) ->
  Prompt = <<"Write 120 characters of 'a', then a newline, then END.">>,
  Opts = openagentic_e2e_online_query:base_runtime_opts(Cfg, TmpProject, #{include_partial_messages => true, tools => []}),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  case {
    openagentic_e2e_online_assert:assert_ok_non_empty(streaming_result, Res),
    openagentic_e2e_online_assert:has_event_type(Events, <<"assistant.delta">>)
  } of
    {ok, true} -> ok;
    {ok, false} -> {warn, {streaming_no_deltas, openagentic_e2e_online_assert:events_summary(Events)}};
    {Err, _} -> Err
  end.

case_session_resume(Cfg, TmpProject) ->
  {Res1, _} =
    openagentic_e2e_online_query:run_query(
      <<"Remember the number 42. Reply only: OK">>,
      openagentic_e2e_online_query:base_runtime_opts(
        Cfg,
        TmpProject,
        #{include_partial_messages => false, tools => []}
      )
    ),
  case Res1 of
    {ok, #{session_id := Sid}} ->
      Opts2 =
        openagentic_e2e_online_query:base_runtime_opts(
          Cfg,
          TmpProject,
          #{include_partial_messages => false, tools => [], resume_session_id => Sid}
        ),
      {Res2, _} =
        openagentic_e2e_online_query:run_query(
          <<"What number did I ask you to remember? Reply with just the number.">>,
          Opts2
        ),
      openagentic_e2e_online_assert:assert_ok_text_contains(resume, Res2, <<"42">>);
    _ ->
      {error, {resume_missing_session_id, Res1}}
  end.

case_tools_list_read_grep_glob(Cfg, TmpProject) ->
  NonceLine = openagentic_e2e_online_fixtures:expected_nonce_line(TmpProject),
  ToolMods = [openagentic_tool_list, openagentic_tool_read, openagentic_tool_grep, openagentic_tool_glob],
  Prompt =
    <<
      "Automated test. Do the following using tools:\n"
      "1) List directory '.' with limit 20.\n"
      "2) Read file 'nonce.txt'.\n"
      "3) Grep for 'needle' in '.'\n"
      "4) Glob for '**/*.txt'\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the exact contents of nonce.txt (trim the trailing newline)\n"
      "- Line 2: TOOLS_OK\n"
    >>,
  Opts =
    openagentic_e2e_online_query:base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => legacy,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>],
        max_steps => 12,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(tools_ok, Res, <<"TOOLS_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(tools_nonce, Res, NonceLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>])
  ]).

case_tools_responses_best_effort(Cfg, TmpProject) ->
  NonceLine = openagentic_e2e_online_fixtures:expected_nonce_line(TmpProject),
  ToolMods = [openagentic_tool_list, openagentic_tool_read, openagentic_tool_grep, openagentic_tool_glob],
  Prompt =
    <<
      "Automated test. Do the following using tools:\n"
      "1) List directory '.' with limit 20.\n"
      "2) Read file 'nonce.txt'.\n"
      "3) Grep for 'needle' in '.'\n"
      "4) Glob for '**/*.txt'\n"
      "Then reply with exactly two lines:\n"
      "- Line 1: the exact contents of nonce.txt (trim the trailing newline)\n"
      "- Line 2: TOOLS_R_OK\n"
    >>,
  Opts =
    openagentic_e2e_online_query:base_runtime_opts(
      Cfg,
      TmpProject,
      #{
        include_partial_messages => false,
        tools => ToolMods,
        protocol => responses,
        permission_gate => openagentic_permissions:bypass(),
        allowed_tools => [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>],
        max_steps => 12,
        system_prompt => <<"You are running automated tests. Follow instructions exactly.">>
      }
    ),
  {Res, Events} = openagentic_e2e_online_query:run_query(Prompt, Opts),
  openagentic_e2e_online_assert:first_error([
    openagentic_e2e_online_assert:assert_ok_text_contains(tools_r_ok, Res, <<"TOOLS_R_OK">>),
    openagentic_e2e_online_assert:assert_ok_text_contains(tools_r_nonce, Res, NonceLine),
    openagentic_e2e_online_assert:tool_events_ok_with_results(Events, [<<"List">>, <<"Read">>, <<"Grep">>, <<"Glob">>])
  ]).
