-module(openagentic_dotenv_test).

-include_lib("eunit/include/eunit.hrl").

parse_ignores_comments_and_blank_lines_test() ->
  Env =
    openagentic_dotenv:parse(
      <<
        "# comment\n"
        " \n"
        "OPENAI_API_KEY=abc\n"
        "; another comment\n"
      >>
    ),
  ?assertEqual(<<"abc">>, maps:get(<<"OPENAI_API_KEY">>, Env)).

parse_strips_wrapping_quotes_test() ->
  Env =
    openagentic_dotenv:parse(
      <<
        "A=\" hello \"\n"
        "B='world'\n"
      >>
    ),
  %% Kotlin parity: quoted values keep inner whitespace.
  ?assertEqual(<<" hello ">>, maps:get(<<"A">>, Env)),
  ?assertEqual(<<"world">>, maps:get(<<"B">>, Env)).

parse_supports_export_prefix_test() ->
  Env = openagentic_dotenv:parse(<<"export X=1\n">>),
  ?assertEqual(<<"1">>, maps:get(<<"X">>, Env)).

parse_strips_unquoted_inline_hash_comment_test() ->
  Env =
    openagentic_dotenv:parse(
      <<
        "OPENAI_API_KEY=abc # comment\n"
      >>
    ),
  ?assertEqual(<<"abc">>, maps:get(<<"OPENAI_API_KEY">>, Env)).

parse_allows_trailing_comment_after_quoted_value_test() ->
  Env =
    openagentic_dotenv:parse(
      <<
        "A=\"v\" # comment\n"
        "B='w' # comment\n"
      >>
    ),
  ?assertEqual(<<"v">>, maps:get(<<"A">>, Env)),
  ?assertEqual(<<"w">>, maps:get(<<"B">>, Env)).
