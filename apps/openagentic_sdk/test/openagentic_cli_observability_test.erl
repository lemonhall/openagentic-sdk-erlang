-module(openagentic_cli_observability_test).

-include_lib("eunit/include/eunit.hrl").

tool_use_summary_includes_target_test() ->
  S1 = openagentic_cli:tool_use_summary_for_test(<<"Read">>, #{<<"file_path">> => <<"README.md">>}),
  ?assertMatch({_, _}, binary:match(S1, <<"file_path=README.md">>)),

  S2 = openagentic_cli:tool_use_summary_for_test(<<"WebSearch">>, #{query => <<"erlang agent framework">>, max_results => 3}),
  ?assertMatch({_, _}, binary:match(S2, <<"q=\"erlang agent framework\"">>)),
  ?assertMatch({_, _}, binary:match(S2, <<"max_results=3">>)),

  S3 = openagentic_cli:tool_use_summary_for_test(<<"WebFetch">>, #{url => <<"https://example.com">>, mode => <<"markdown">>}),
  ?assertMatch({_, _}, binary:match(S3, <<"url=https://example.com">>)),
  ?assertMatch({_, _}, binary:match(S3, <<"mode=markdown">>)).

tool_use_summary_redacts_secrets_test() ->
  Secret = <<"sk-1234567890abcdefghijklmnop">>,
  S = openagentic_cli:tool_use_summary_for_test(<<"Bash">>, #{command => iolist_to_binary([<<"echo ">>, Secret])}),
  ?assertEqual(nomatch, binary:match(S, Secret)),
  ?assertMatch({_, _}, binary:match(S, <<"sk-***">>)).

redact_secrets_bearer_test() ->
  In = <<"Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789-_">>,
  Out = openagentic_cli:redact_secrets_for_test(In),
  ?assertEqual(nomatch, binary:match(Out, <<"abcdefghijklmnopqrstuvwxyz">>)),
  ?assertMatch({_, _}, binary:match(Out, <<"Bearer ***">>)).

tool_result_lines_websearch_summary_test() ->
  Out = #{
    total_results => 5,
    results => [
      #{title => <<"A">>, url => <<"https://a.example">>},
      #{title => <<"B">>, url => <<"https://b.example">>},
      #{title => <<"C">>, url => <<"https://c.example">>},
      #{title => <<"D">>, url => <<"https://d.example">>}
    ]
  },
  Lines = openagentic_cli:tool_result_lines_for_test(<<"WebSearch">>, Out),
  ?assertEqual(4, length(Lines)),
  [Head | Items] = Lines,
  ?assertMatch({_, _}, binary:match(Head, <<"total=5">>)),
  lists:foreach(
    fun (L) ->
      ?assertMatch({0, _}, binary:match(L, <<"- ">>))
    end,
    Items
  ).

