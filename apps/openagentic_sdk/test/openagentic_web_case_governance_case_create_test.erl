-module(openagentic_web_case_governance_case_create_test).

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

