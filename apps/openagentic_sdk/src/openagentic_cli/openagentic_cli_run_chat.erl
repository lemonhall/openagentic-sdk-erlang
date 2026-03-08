-module(openagentic_cli_run_chat).
-export([run_cmd/1,chat_cmd/1,chat_loop/2]).

run_cmd(Args0) ->
  {Flags, Pos} = openagentic_cli_flags:parse_flags(Args0, #{}),
  Prompt0 = string:trim(iolist_to_binary(lists:join(" ", Pos))),
  case byte_size(Prompt0) > 0 of
    false ->
      io:format("Missing prompt.~n~n", []),
      openagentic_cli_main:usage(),
      halt(2);
    true ->
      Opts = openagentic_cli_runtime_opts:runtime_opts(Flags),
      case openagentic_runtime:query(Prompt0, Opts) of
        {ok, #{session_id := Sid}} ->
          io:format("~nsession_id=~s~n", [openagentic_cli_values:to_list(Sid)]),
          ok;
        {error, Reason} ->
          io:format("~nERROR: ~p~n", [Reason]),
          halt(1)
      end
  end.

chat_cmd(Args0) ->
  {Flags, _Pos} = openagentic_cli_flags:parse_flags(Args0, #{}),
  Opts0 = openagentic_cli_runtime_opts:runtime_opts(Flags),
  Resume0 = maps:get(resume_session_id, Opts0, undefined),
  SessionId0 =
    case Resume0 of
      undefined -> undefined;
      <<>> -> undefined;
      "" -> undefined;
      V -> openagentic_cli_values:to_bin(V)
    end,
  io:format("Chat mode. Type /exit to quit.~n", []),
  chat_loop(SessionId0, Opts0).

chat_loop(SessionId0, Opts0) ->
  Line0 = io:get_line("> "),
  case Line0 of
    eof ->
      io:format("~n", []),
      ok;
    _ ->
      Line = string:trim(openagentic_cli_values:to_bin(Line0)),
      case Line of
        <<>> ->
          chat_loop(SessionId0, Opts0);
        <<"/exit">> ->
          ok;
        _ ->
          Opts =
            case SessionId0 of
              undefined -> Opts0;
              Sid -> Opts0#{resume_session_id => Sid}
            end,
          case openagentic_runtime:query(Line, Opts) of
            {ok, #{session_id := Sid2}} ->
              io:format("~n", []),
              chat_loop(openagentic_cli_values:to_bin(Sid2), Opts0);
            {error, Reason} ->
              io:format("~nERROR: ~p~n", [Reason]),
              chat_loop(SessionId0, Opts0)
          end
      end
  end.
