-module(openagentic_web_api_questions_answer).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State0) ->
  State = ensure_map(State0),
  {ok, BodyBin, Req1} = cowboy_req:read_body(Req0),
  Body = string:trim(BodyBin),
  case decode_json(Body) of
    {ok, Obj} ->
      Qid = to_bin(maps:get(<<"question_id">>, Obj, maps:get(<<"questionId">>, Obj, <<>>))),
      Ans = maps:get(<<"answer">>, Obj, maps:get(answer, Obj, <<>>)),
      case byte_size(string:trim(Qid)) > 0 of
        false ->
          reply_json(400, #{error => <<"missing question_id">>}, Req1, State);
        true ->
          ok = openagentic_web_q:answer(Qid, Ans),
          reply_json(200, #{ok => true}, Req1, State)
      end;
    {error, _} ->
      reply_json(400, #{error => <<"invalid json">>}, Req1, State)
  end.

decode_json(<<>>) -> {error, empty};
decode_json(Bin) ->
  try
    {ok, openagentic_json:decode(Bin)}
  catch
    _:_ -> {error, invalid}
  end.

reply_json(Status, Obj0, Req0, State) ->
  Obj = ensure_map(Obj0),
  Body = openagentic_json:encode_safe(Obj),
  Req1 =
    cowboy_req:reply(
      Status,
      #{<<"content-type">> => <<"application/json">>, <<"cache-control">> => <<"no-store">>},
      Body,
      Req0
    ),
  {ok, Req1, State}.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
