-module(openagentic_fs_tools_test_support).
-export([has_match_file/2, has_subpath/2, norm/1, test_root/0]).

has_subpath(Files, Sub0) ->
  Sub = norm(Sub0),
  lists:any(fun(F) -> binary:match(norm(F), Sub) =/= nomatch end, Files).

has_match_file(Matches, Sub0) ->
  Sub = norm(Sub0),
  lists:any(
    fun(M) ->
      P = maps:get(file_path, M, <<>>),
      binary:match(norm(P), Sub) =/= nomatch
    end,
    Matches
  ).

norm(B) when is_binary(B) ->
  iolist_to_binary(string:replace(B, <<"\\">>, <<"/">>, all));
norm(L) when is_list(L) ->
  norm(iolist_to_binary(L));
norm(Other) ->
  norm(iolist_to_binary(io_lib:format("~p", [Other]))).

test_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([Cwd, ".tmp", "eunit", "openagentic_fs_tools_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Tmp = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Tmp, "x"])),
  Tmp.
