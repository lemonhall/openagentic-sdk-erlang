-module(openagentic_cli).

-export([main/1]).

-ifdef(TEST).
-export([parse_flags_for_test/1, runtime_opts_for_test/1]).
-endif.

main(Args0) ->
  Args = ensure_list(Args0),
  case Args of
    ["run" | Rest] ->
      run_cmd(Rest);
    ["chat" | Rest] ->
      chat_cmd(Rest);
    ["-h"] ->
      usage();
    ["--help"] ->
      usage();
    _ ->
      usage()
  end.

run_cmd(Args0) ->
  {Flags, Pos} = parse_flags(Args0, #{}),
  Prompt0 = string:trim(iolist_to_binary(lists:join(" ", Pos))),
  case byte_size(Prompt0) > 0 of
    false ->
      io:format("Missing prompt.~n~n", []),
      usage(),
      halt(2);
    true ->
      Opts = runtime_opts(Flags),
      case openagentic_runtime:query(Prompt0, Opts) of
        {ok, #{session_id := Sid}} ->
          io:format("~nsession_id=~s~n", [to_list(Sid)]),
          ok;
        {error, Reason} ->
          io:format("~nERROR: ~p~n", [Reason]),
          halt(1)
      end
  end.

chat_cmd(Args0) ->
  {Flags, _Pos} = parse_flags(Args0, #{}),
  Opts0 = runtime_opts(Flags),
  Resume0 = maps:get(resume_session_id, Opts0, undefined),
  SessionId0 =
    case Resume0 of
      undefined -> undefined;
      <<>> -> undefined;
      "" -> undefined;
      V -> to_bin(V)
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
      Line = string:trim(to_bin(Line0)),
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
              chat_loop(to_bin(Sid2), Opts0);
            {error, Reason} ->
              io:format("~nERROR: ~p~n", [Reason]),
              chat_loop(SessionId0, Opts0)
          end
      end
  end.

usage() ->
  io:format(
    "openagentic (Erlang)\\n\\n"
    "Usage:\\n"
    "  openagentic run [flags] <prompt>\\n"
    "  openagentic chat [flags]\\n\\n"
    "Flags:\\n"
    "  --protocol <responses|legacy>\\n"
    "  --model <model>\\n"
    "  --base-url <url>\\n"
    "  --resume <session_id>\\n"
    "  --permission <bypass|deny|prompt|default>\\n"
    "  --stream\\n"
    "  --no-stream\\n"
    "  --max-steps <1..200>\\n"
    "  --context-limit <n>\\n"
    "  --reserved <n>\\n"
    "  --input-limit <n>\\n\\n"
    "Env (preferred):\\n"
    "  OPENAI_API_KEY (required)\\n"
    "  OPENAI_BASE_URL (optional)\\n"
    "  OPENAI_MODEL (optional)\\n",
    []
  ).

-ifdef(TEST).
parse_flags_for_test(Args0) ->
  parse_flags(ensure_list(Args0), #{}).

runtime_opts_for_test(Flags0) ->
  runtime_opts(ensure_map(Flags0)).
-endif.

runtime_opts(Flags0) ->
  Flags = ensure_map(Flags0),
  ApiKey =
    case os:getenv("OPENAI_API_KEY") of
      false -> undefined;
      ApiKeyEnv -> iolist_to_binary(ApiKeyEnv)
    end,
  Model =
    case maps:get(model, Flags, undefined) of
      undefined ->
        case os:getenv("OPENAI_MODEL") of
          false -> undefined;
          ModelEnv -> iolist_to_binary(ModelEnv)
        end;
      ModelFlag -> to_bin(ModelFlag)
    end,
  BaseUrl =
    case maps:get(base_url, Flags, undefined) of
      undefined ->
        case os:getenv("OPENAI_BASE_URL") of
          false -> undefined;
          BaseUrlEnv -> iolist_to_binary(BaseUrlEnv)
        end;
      BaseUrlFlag -> to_bin(BaseUrlFlag)
    end,
  Protocol = maps:get(protocol, Flags, responses),
  Stream = maps:get(stream, Flags, true),
  Permission = maps:get(permission, Flags, default),
  Resume = maps:get(resume_session_id, Flags, undefined),
  MaxSteps = maps:get(max_steps, Flags, 20),
  Compaction = ensure_map(maps:get(compaction, Flags, #{})),

  UserAnswerer = fun ask_user_answerer/1,
  Gate =
    case Permission of
      bypass -> openagentic_permissions:bypass();
      deny -> openagentic_permissions:deny();
      prompt -> openagentic_permissions:prompt(UserAnswerer);
      default -> openagentic_permissions:default(UserAnswerer);
      _ -> openagentic_permissions:default(UserAnswerer)
    end,

  Explore = openagentic_built_in_subagents:explore_agent(),
  TaskAgents = [Explore],

  case {ApiKey, Model} of
    {undefined, _} ->
      io:format("Missing env OPENAI_API_KEY.~n", []),
      halt(2);
    {_, undefined} ->
      io:format("Missing model. Use --model or env OPENAI_MODEL.~n", []),
      halt(2);
    _ ->
      ok
  end,

  #{
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    protocol => Protocol,
    include_partial_messages => Stream,
    resume_session_id => Resume,
    max_steps => MaxSteps,
    compaction => Compaction,
    permission_gate => Gate,
    user_answerer => UserAnswerer,
    task_progress_emitter => fun (Msg) -> io:format("~s~n", [to_list(Msg)]) end,
    task_agents => TaskAgents,
    event_sink => event_sink(Stream)
  }.

ask_user_answerer(Question0) ->
  Q = ensure_map(Question0),
  Prompt = to_bin(maps:get(prompt, Q, maps:get(<<"prompt">>, Q, <<>>))),
  Choices0 = ensure_list(maps:get(choices, Q, maps:get(<<"choices">>, Q, []))),
  Choices = [to_bin(C) || C <- Choices0],
  io:format("~n~s~n", [to_list(Prompt)]),
  case Choices of
    [] ->
      io:get_line("answer> ");
    _ ->
      lists:foreach(fun (C) -> io:format("  - ~s~n", [to_list(C)]) end, Choices),
      Ans0 = io:get_line("answer> "),
      string:trim(to_bin(Ans0))
  end.

event_sink(Stream) ->
  fun (Ev0) ->
    Ev = ensure_map(Ev0),
    Type = to_bin(maps:get(type, Ev, maps:get(<<"type">>, Ev, <<>>))),
    case Type of
      <<"assistant.delta">> ->
        Delta = to_bin(maps:get(text_delta, Ev, maps:get(<<"text_delta">>, Ev, <<>>))),
        put(last_was_delta, true),
        io:put_chars(Delta);
      <<"assistant.message">> ->
        LastDelta = get(last_was_delta),
        case {Stream, LastDelta} of
          {true, true} ->
            put(last_was_delta, false),
            io:format("~n", []);
          _ ->
            Txt = to_bin(maps:get(text, Ev, maps:get(<<"text">>, Ev, <<>>))),
            io:format("assistant: ~s~n", [to_list(Txt)])
        end;
      <<"tool.use">> ->
        maybe_break_delta(),
        Name = to_bin(maps:get(name, Ev, maps:get(<<"name">>, Ev, <<>>))),
        io:format("tool.use ~s~n", [to_list(Name)]);
      <<"tool.result">> ->
        maybe_break_delta(),
        IsError = maps:get(is_error, Ev, maps:get(<<"is_error">>, Ev, false)),
        case IsError of
          true ->
            Et = to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<"error">>))),
            Em = to_bin(maps:get(error_message, Ev, maps:get(<<"error_message">>, Ev, <<>>))),
            io:format("tool.result ERROR ~s: ~s~n", [to_list(Et), to_list(Em)]);
          false ->
            io:format("tool.result ok~n", [])
        end;
      <<"runtime.error">> ->
        maybe_break_delta(),
        Phase = to_bin(maps:get(phase, Ev, maps:get(<<"phase">>, Ev, <<>>))),
        Et = to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<>>))),
        io:format("runtime.error ~s ~s~n", [to_list(Phase), to_list(Et)]);
      <<"result">> ->
        maybe_break_delta(),
        Stop = to_bin(maps:get(stop_reason, Ev, maps:get(<<"stop_reason">>, Ev, <<>>))),
        io:format("result stop_reason=~s~n", [to_list(Stop)]);
      _ ->
        ok
    end
  end.

maybe_break_delta() ->
  case get(last_was_delta) of
    true ->
      put(last_was_delta, false),
      io:format("~n", []);
    _ ->
      ok
  end.

parse_flags([], Acc) ->
  {Acc, []};
parse_flags(["--protocol", V | Rest], Acc) ->
  {P, _} = {openagentic_provider_protocol:normalize(V), V},
  parse_flags(Rest, Acc#{protocol => P});
parse_flags(["--model", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{model => to_bin(V)});
parse_flags(["--base-url", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{base_url => to_bin(V)});
parse_flags(["--resume", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{resume_session_id => to_bin(V)});
parse_flags(["--permission", V0 | Rest], Acc) ->
  V = string:lowercase(string:trim(to_bin(V0))),
  Mode =
    case V of
      <<"bypass">> -> bypass;
      <<"deny">> -> deny;
      <<"prompt">> -> prompt;
      <<"default">> -> default;
      _ -> default
    end,
  parse_flags(Rest, Acc#{permission => Mode});
parse_flags(["--stream" | Rest], Acc) ->
  parse_flags(Rest, Acc#{stream => true});
parse_flags(["--no-stream" | Rest], Acc) ->
  parse_flags(Rest, Acc#{stream => false});
parse_flags(["--max-steps", V0 | Rest], Acc) ->
  Max0 = parse_int(V0),
  Max =
    case Max0 of
      I when is_integer(I) -> clamp_int(I, 1, 200);
      _ -> 20
    end,
  parse_flags(Rest, Acc#{max_steps => Max});
parse_flags(["--context-limit", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, context_limit, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["--reserved", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, reserved, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["--input-limit", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, input_limit, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["-h" | _Rest], _Acc) ->
  usage(),
  halt(0);
parse_flags(["--help" | _Rest], _Acc) ->
  usage(),
  halt(0);
parse_flags([Arg | Rest], Acc) ->
  {Acc2, Pos} = parse_flags(Rest, Acc),
  {Acc2, [Arg | Pos]}.

set_compaction_opt(Acc0, K, V) ->
  Acc = ensure_map(Acc0),
  Comp0 = ensure_map(maps:get(compaction, Acc, #{})),
  Acc#{compaction => Comp0#{K => V}}.

parse_int(V0) ->
  case (catch binary_to_integer(string:trim(to_bin(V0)))) of
    I when is_integer(I) -> I;
    _ -> undefined
  end.

clamp_int(I, Min, Max) when is_integer(I) ->
  erlang:min(Max, erlang:max(Min, I)).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [binary_to_list(B)];
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
