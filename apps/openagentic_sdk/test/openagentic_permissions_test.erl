-module(openagentic_permissions_test).

-include_lib("eunit/include/eunit.hrl").

default_allows_safe_tools_with_schema_test() ->
  Gate = openagentic_permissions:default(undefined),
  Ctx = #{session_id => <<"s">>, tool_use_id => <<"t1">>},
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"List">>, #{path => <<"./">>}, Ctx)),
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"Read">>, #{file_path => <<"x.txt">>}, Ctx)),
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"Glob">>, #{pattern => <<"*.erl">>}, Ctx)),
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"Grep">>, #{query => <<"foo">>}, Ctx)),
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"WebFetch">>, #{url => <<"https://example.com/">>}, Ctx)),
  ?assertMatch(#{allowed := true}, openagentic_permissions:approve(Gate, <<"WebSearch">>, #{query => <<"erlang agent">>}, Ctx)).

default_denies_safe_tools_bad_schema_test() ->
  Gate = openagentic_permissions:default(undefined),
  Ctx = #{tool_use_id => <<"t2">>},
  Res = openagentic_permissions:approve(Gate, <<"Read">>, #{}, Ctx),
  ?assertEqual(false, maps:get(allowed, Res)),
  ?assert(is_binary(maps:get(deny_message, Res))).

deny_mode_denies_test() ->
  Gate = openagentic_permissions:deny(),
  Res = openagentic_permissions:approve(Gate, <<"Write">>, #{}, #{}),
  ?assertEqual(false, maps:get(allowed, Res)).

prompt_requires_answerer_test() ->
  Gate = openagentic_permissions:default(undefined),
  %% "Write" is not safe in DEFAULT => should fallthrough to prompt and fail without answerer.
  Res = openagentic_permissions:approve(Gate, <<"Write">>, #{}, #{tool_use_id => <<"x">>}),
  ?assertEqual(false, maps:get(allowed, Res)),
  ?assert(is_binary(maps:get(deny_message, Res))).

prompt_allows_on_yes_test() ->
  Answerer = fun (_Q) -> <<"yes">> end,
  Gate = openagentic_permissions:prompt(Answerer),
  Res = openagentic_permissions:approve(Gate, <<"Write">>, #{}, #{tool_use_id => <<"x">>}),
  ?assertEqual(true, maps:get(allowed, Res)).

prompt_denies_and_passes_free_text_answer_test() ->
  Answerer = fun (_Q) -> <<"别使用bash啊">> end,
  Gate = openagentic_permissions:prompt(Answerer),
  Res = openagentic_permissions:approve(Gate, <<"Bash">>, #{command => <<"git status">>}, #{tool_use_id => <<"x">>}),
  ?assertEqual(false, maps:get(allowed, Res)),
  Deny = maps:get(deny_message, Res),
  ?assert(is_binary(Deny)),
  ?assertMatch({_, _}, binary:match(Deny, <<"别使用bash啊">>)).
