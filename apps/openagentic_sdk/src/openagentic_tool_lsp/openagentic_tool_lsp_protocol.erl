-module(openagentic_tool_lsp_protocol).

-export([rpc_notify/3, rpc_request/6]).

rpc_notify(Port, Method, Params) ->
  Msg = #{
    <<"jsonrpc">> => <<"2.0">>,
    <<"method">> => Method,
    <<"params">> => Params
  },
  send_jsonrpc(Port, Msg).

rpc_request(Port, Buf0, State0, Method, Params, TimeoutMs) ->
  Id = maps:get(next_id, State0, 1),
  State1 = State0#{next_id := Id + 1},
  Req = #{
    <<"jsonrpc">> => <<"2.0">>,
    <<"id">> => Id,
    <<"method">> => Method,
    <<"params">> => Params
  },
  ok = send_jsonrpc(Port, Req),
  {Buf1, Resp} = recv_response_id(Port, Buf0, Id, TimeoutMs),
  Result = maps:get(<<"result">>, Resp, null),
  {Buf1, Result, State1}.

recv_response_id(Port, Buf0, Id, TimeoutMs) ->
  Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
  recv_loop(Port, Buf0, Id, Deadline).

recv_loop(Port, Buf0, Id, Deadline) ->
  Now = erlang:monotonic_time(millisecond),
  Remaining = erlang:max(0, Deadline - Now),
  case parse_one(Buf0) of
    {ok, Msg, Rest} ->
      case maps:get(<<"id">>, Msg, undefined) of
        Id ->
          {Rest, Msg};
        _ ->
          recv_loop(Port, Rest, Id, Deadline)
      end;
    more ->
      receive
        {Port, {data, Bin}} when is_binary(Bin) ->
          recv_loop(Port, <<Buf0/binary, Bin/binary>>, Id, Deadline);
        {Port, {exit_status, Code}} ->
          throw({runtime_error, iolist_to_binary([<<"lsp: server exited: ">>, integer_to_binary(Code)])})
      after Remaining ->
        throw({runtime_error, <<"lsp: timeout waiting for response">>})
      end
  end.

send_jsonrpc(Port, Obj) ->
  Body = openagentic_json:encode(Obj),
  Header = iolist_to_binary([<<"Content-Length: ">>, integer_to_binary(byte_size(Body)), <<"\r\n\r\n">>]),
  port_command(Port, <<Header/binary, Body/binary>>),
  ok.

parse_one(Buf) ->
  case binary:match(Buf, <<"\r\n\r\n">>) of
    nomatch ->
      more;
    {HdrEnd, _} ->
      HeaderBin = binary:part(Buf, 0, HdrEnd),
      Rest0 = binary:part(Buf, HdrEnd + 4, byte_size(Buf) - (HdrEnd + 4)),
      case parse_content_length(HeaderBin) of
        {ok, Len} ->
          case byte_size(Rest0) >= Len of
            true ->
              Body = binary:part(Rest0, 0, Len),
              Rest = binary:part(Rest0, Len, byte_size(Rest0) - Len),
              {ok, openagentic_tool_lsp_utils:ensure_map(openagentic_json:decode(Body)), Rest};
            false ->
              more
          end;
        _ ->
          more
      end
  end.

parse_content_length(HeaderBin) ->
  Lines = binary:split(HeaderBin, <<"\r\n">>, [global]),
  parse_len_lines(Lines).

parse_len_lines([]) -> {error, no_length};
parse_len_lines([L | T]) ->
  case string:lowercase(L) of
    <<"content-length:", Rest/binary>> ->
      Val = string:trim(Rest),
      case (catch binary_to_integer(Val)) of
        I when is_integer(I) -> {ok, I};
        _ -> {error, bad_length}
      end;
    _ ->
      parse_len_lines(T)
  end.
