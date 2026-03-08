-module(openagentic_session_store_layout).

-export([new_session_id/0, session_dir/2]).

session_dir(RootDir0, SessionId0) ->
  RootDir = openagentic_session_store_utils:ensure_list(RootDir0),
  SessionId = openagentic_session_store_utils:ensure_list(SessionId0),
  Sid = string:trim(SessionId),
  case is_valid_sid(Sid) of
    true -> filename:join([RootDir, "sessions", Sid]);
    false -> erlang:error({invalid_session_id, Sid})
  end.

new_session_id() ->
  hex_lower(crypto:strong_rand_bytes(16)).

hex_lower(Bin) ->
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bin]).

is_valid_sid(Sid) when is_list(Sid) ->
  length(Sid) =:= 32 andalso lists:all(fun is_hex/1, Sid).

is_hex(C) when C >= $0, C =< $9 -> true;
is_hex(C) when C >= $a, C =< $f -> true;
is_hex(C) when C >= $A, C =< $F -> true;
is_hex(_) -> false.
