-module(openagentic_compaction_test).

-include_lib("eunit/include/eunit.hrl").

would_overflow_boundary_test() ->
  Compaction = #{context_limit => 10000, reserved => 2000, global_output_cap => 4096},
  UsageOk = #{<<"total_tokens">> => 7999},
  UsageEdge = #{<<"total_tokens">> => 8000},
  ?assertEqual(false, openagentic_compaction:would_overflow(Compaction, UsageOk)),
  ?assertEqual(true, openagentic_compaction:would_overflow(Compaction, UsageEdge)),
  ok.

select_tool_outputs_to_prune_skips_last_two_turns_and_applies_thresholds_test() ->
  %% Kotlin parity:
  %% - Skip pruning until >=2 user turns are present (so the newest 2 turns are never pruned).
  %% - Only apply if pruned_tokens > min_prune_tokens (strict).
  Big = binary:copy(<<"x">>, 2000),
  Events = [
    #{type => <<"assistant.message">>, text => <<"summary pivot">>, is_summary => true},
    #{type => <<"user.message">>, text => <<"t1">>},
    #{type => <<"assistant.message">>, text => <<"a1">>},
    #{type => <<"tool.use">>, tool_use_id => <<"tid1">>, name => <<"Read">>, input => #{}},
    #{type => <<"tool.result">>, tool_use_id => <<"tid1">>, output => #{<<"data">> => Big}, is_error => false},
    #{type => <<"user.message">>, text => <<"t2">>},
    #{type => <<"assistant.message">>, text => <<"a2">>},
    #{type => <<"tool.use">>, tool_use_id => <<"tid2">>, name => <<"Read">>, input => #{}},
    #{type => <<"tool.result">>, tool_use_id => <<"tid2">>, output => #{<<"data">> => Big}, is_error => false},
    #{type => <<"user.message">>, text => <<"t3">>},
    #{type => <<"assistant.message">>, text => <<"a3">>},
    #{type => <<"tool.use">>, tool_use_id => <<"tid3">>, name => <<"Read">>, input => #{}},
    #{type => <<"tool.result">>, tool_use_id => <<"tid3">>, output => #{<<"data">> => Big}, is_error => false}
  ],
  Compaction = #{prune => true, protect_tool_output_tokens => 10, min_prune_tokens => 1},
  Ids = openagentic_compaction:select_tool_outputs_to_prune(Events, Compaction),
  ?assert(lists:member(<<"tid1">>, Ids)),
  ?assertNot(lists:member(<<"tid2">>, Ids)),
  ?assertNot(lists:member(<<"tid3">>, Ids)),
  ok.
