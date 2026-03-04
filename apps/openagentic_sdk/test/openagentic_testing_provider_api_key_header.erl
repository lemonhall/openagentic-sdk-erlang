-module(openagentic_testing_provider_api_key_header).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(Req0) ->
  Req = ensure_map(Req0),
  Expected = get(expected_api_key_header),
  Got = maps:get(api_key_header, Req, undefined),
  case Expected of
    undefined ->
      ok;
    _ when Got =:= Expected ->
      ok;
    _ ->
      erlang:error({expected_api_key_header, Expected, Got, Req})
  end,
  {ok, #{assistant_text => <<>>, tool_calls => [], response_id => <<"resp_hdr_1">>, usage => #{}}}.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

