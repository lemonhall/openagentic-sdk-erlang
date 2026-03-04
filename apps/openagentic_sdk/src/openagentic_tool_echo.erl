-module(openagentic_tool_echo).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Echo">>.

description() -> <<"Echo back the provided text.">>.

run(Input0, _Ctx) ->
  Input = ensure_map(Input0),
  Text = maps:get(<<"text">>, Input, maps:get(text, Input, <<>>)),
  {ok, #{text => Text}}.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

