-module(openagentic_cli).

-export([main/1]).

-ifdef(TEST).
-export([
  parse_flags_for_test/1,
  runtime_opts_for_test/1,
  resolve_project_dir_for_test/1,
  tool_use_summary_for_test/2,
  tool_result_lines_for_test/2,
  redact_secrets_for_test/1
]).
-endif.

-ifdef(TEST).
tool_use_summary_for_test(Name0, Input0) ->
  tool_use_summary(to_bin(Name0), ensure_map(Input0)).

tool_result_lines_for_test(Name0, Output0) ->
  tool_result_lines(to_bin(Name0), Output0).

redact_secrets_for_test(Bin0) ->
  redact_secrets(to_bin(Bin0)).
-endif.

main(Args0) ->
  Args = ensure_list(Args0),
  case Args of
    ["run" | Rest] ->
      run_cmd(Rest);
    ["chat" | Rest] ->
      chat_cmd(Rest);
    ["workflow" | Rest] ->
      workflow_cmd(Rest);
    ["web" | Rest] ->
      web_cmd(Rest);
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

workflow_cmd(Args0) ->
  {Flags, Pos} = parse_flags(Args0, #{}),
  Prompt0 = string:trim(iolist_to_binary(lists:join(" ", Pos))),
  case byte_size(Prompt0) > 0 of
    false ->
      io:format("Missing prompt.~n~n", []),
      usage(),
      halt(2);
    true ->
      Dsl0 = maps:get(workflow_dsl, Flags, maps:get(workflowDsl, Flags, undefined)),
      Dsl1 = string:trim(to_bin(Dsl0)),
      Dsl =
        case Dsl1 of
          <<>> -> <<"workflows/three-provinces-six-ministries.v1.json">>;
          <<"undefined">> -> <<"workflows/three-provinces-six-ministries.v1.json">>;
          _ -> Dsl1
        end,
      Opts = runtime_opts(Flags),
      ProjectDir = ensure_list(maps:get(project_dir, Opts, ".")),
      EngineOpts = Opts#{strict_unknown_fields => true},
      case openagentic_workflow_engine:run(ProjectDir, to_list(Dsl), Prompt0, EngineOpts) of
        {ok, Res} ->
          WfId = to_bin(maps:get(workflow_id, Res, <<>>)),
          Sid = to_bin(maps:get(workflow_session_id, Res, <<>>)),
          io:format("~nworkflow_id=~s~nworkflow_session_id=~s~n", [to_list(WfId), to_list(Sid)]),
          ok;
        {error, Reason} ->
          io:format("~nERROR: ~p~n", [Reason]),
          halt(1)
      end
  end.

web_cmd(Args0) ->
  {Flags, _Pos} = parse_flags(Args0, #{}),
  Opts0 = runtime_opts(Flags),
  %% Web UI uses its own HITL channel (/api/questions/answer). Avoid console prompts in server mode.
  Opts1 = Opts0#{user_answerer => undefined, permission_gate => openagentic_permissions:default(undefined)},
  Bind0 = maps:get(web_bind, Flags, maps:get(webBind, Flags, undefined)),
  Port0 = maps:get(web_port, Flags, maps:get(webPort, Flags, undefined)),
  Opts =
    Opts1#{
      web_bind => to_bin(Bind0),
      web_port => Port0
    },
  case start_web_runtime_unlinked(Opts) of
    {ok, #{url := Url}} ->
      io:format("~nWeb UI: ~ts~n", [to_text(Url)]),
      ok;
    {error, Reason} ->
      io:format("~nERROR: ~p~n", [Reason]),
      halt(1)
  end.

start_web_runtime_unlinked(Opts) ->
  Parent = self(),
  Ref = make_ref(),
  {Pid, MRef} =
    spawn_monitor(
      fun () ->
        Parent ! {web_start_result, Ref, openagentic_web:start(Opts)}
      end
    ),
  receive
    {web_start_result, Ref, Res} ->
      _ = erlang:demonitor(MRef, [flush]),
      Res;
    {'DOWN', MRef, process, Pid, Reason} ->
      receive
        {web_start_result, Ref, Res2} -> Res2
      after 50 ->
        {error, {web_start_failed, Reason}}
      end
  end.

usage() ->
  io:format(
    "openagentic (Erlang)\\n\\n"
    "Usage:\\n"
    "  openagentic run [flags] <prompt>\\n"
    "  openagentic chat [flags]\\n"
    "  openagentic workflow [flags] [--dsl <path>] <prompt>\\n\\n"
    "  openagentic web [flags] [--web-bind <ip>] [--web-port <port>]\\n\\n"
    "Defaults:\\n"
    "  - Reads .env in project dir (if present)\\n"
    "  - Project dir defaults to current directory\\n"
    "  - Streaming defaults to on\\n"
    "  - Colors default to on (set NO_COLOR=1 to disable)\\n\\n"
    "Flags:\\n"
    "  --protocol <responses|legacy>\\n"
    "  --model <model>\\n"
    "  --api-key <key>\\n"
    "  --base-url <url>\\n"
    "  --api-key-header <header>\\n"
    "  --cwd <dir> (legacy alias; prefer --project-dir)\\n"
    "  --project-dir <dir>\\n"
    "  --resume <session_id>\\n"
    "  --permission <bypass|deny|prompt|default>\\n"
    "  --stream\\n"
    "  --no-stream\\n"
    "  --color\\n"
    "  --no-color\\n"
    "  --render-markdown (only affects non-stream output)\\n"
    "  --no-render-markdown\\n"
    "  --openai-store <bool>\\n"
    "  --no-openai-store\\n"
    "  --max-steps <1..200>\\n"
    "  --context-limit <n>\\n"
    "  --reserved <n>\\n"
    "  --input-limit <n>\\n"
    "  --dsl <path> (workflow DSL; default: workflows/three-provinces-six-ministries.v1.json)\\n\\n"
    "  --web-bind <ip> (web UI bind; default: 127.0.0.1)\\n"
    "  --web-port <port> (web UI port; default: 8088)\\n\\n"
    "Env/.env keys:\\n"
    "  OPENAI_API_KEY (required)\\n"
    "  OPENAI_BASE_URL (optional)\\n"
    "  OPENAI_MODEL or MODEL (optional)\\n"
    "  OPENAI_API_KEY_HEADER (optional)\\n"
    "  OPENAI_STORE (optional)\\n",
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
  %% Kotlin CLI runs as a normal process so cwd is the project directory.
  %% When running this Erlang CLI from `rebar3 shell`, cwd can be under `_build/`.
  %% To reduce surprises, when project dir is not explicitly provided we search upwards
  %% for a `.env` (or `rebar.config`) and treat that directory as project dir.
  ExplicitProjectDir = maps:get(project_dir, Flags, maps:get(cwd, Flags, undefined)),
  ProjectDir0 =
    case ExplicitProjectDir of
      undefined -> cwd_safe();
      V -> V
    end,
  UsedDefault = ExplicitProjectDir =:= undefined,
  ProjectDir1 = to_list(string:trim(to_bin(ProjectDir0))),
  ProjectDir = case UsedDefault of true -> resolve_project_dir(ProjectDir1); false -> ProjectDir1 end,
  DotEnv = openagentic_dotenv:load(filename:join([ProjectDir, ".env"])),

  ApiKey =
    first_non_blank([
      maps:get(api_key, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_API_KEY">>, DotEnv),
      os:getenv("OPENAI_API_KEY")
    ]),

  Model =
    first_non_blank([
      maps:get(model, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_MODEL">>, DotEnv),
      openagentic_dotenv:get(<<"MODEL">>, DotEnv),
      os:getenv("OPENAI_MODEL"),
      os:getenv("MODEL")
    ]),

  BaseUrl =
    first_non_blank([
      maps:get(base_url, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_BASE_URL">>, DotEnv),
      os:getenv("OPENAI_BASE_URL"),
      <<"https://api.openai.com/v1">>
    ]),

  ApiKeyHeader =
    first_non_blank([
      maps:get(api_key_header, Flags, undefined),
      openagentic_dotenv:get(<<"OPENAI_API_KEY_HEADER">>, DotEnv),
      os:getenv("OPENAI_API_KEY_HEADER"),
      <<"authorization">>
    ]),
  Protocol = maps:get(protocol, Flags, responses),
  Stream = maps:get(stream, Flags, true),
  ColorFlag = maps:get(color, Flags, undefined),
  Color =
    case ColorFlag of
      true -> true;
      false -> false;
      _ -> auto_color()
    end,
  RenderMarkdown = to_bool_default(maps:get(render_markdown, Flags, true), true),
  Permission = maps:get(permission, Flags, default),
  Resume = maps:get(resume_session_id, Flags, undefined),
  MaxSteps = maps:get(max_steps, Flags, 50),
  Compaction = ensure_map(maps:get(compaction, Flags, #{})),
  OpenAiStore0 =
    case maps:is_key(openai_store, Flags) of
      true -> maps:get(openai_store, Flags);
      false -> first_non_blank([openagentic_dotenv:get(<<"OPENAI_STORE">>, DotEnv), os:getenv("OPENAI_STORE")])
    end,
  OpenAiStore = to_bool_default(OpenAiStore0, true),

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
  Research = openagentic_built_in_subagents:research_agent(),
  TaskAgents = [Explore, Research],

  case {ApiKey, Model} of
    {undefined, _} ->
      io:format("Missing API key. Use --api-key, or set OPENAI_API_KEY (env/.env).~n", []),
      halt(2);
    {_, undefined} ->
      io:format("Missing model. Use --model, or set OPENAI_MODEL/MODEL (env/.env).~n", []),
      halt(2);
    _ ->
      ok
  end,

  #{
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    api_key_header => ApiKeyHeader,
    protocol => Protocol,
    include_partial_messages => Stream,
    resume_session_id => Resume,
    max_steps => MaxSteps,
    compaction => Compaction,
    openai_store => OpenAiStore,
    cwd => ProjectDir,
    project_dir => ProjectDir,
    permission_gate => Gate,
    user_answerer => UserAnswerer,
    task_progress_emitter => fun (Msg) -> io:format("~ts~n", [to_text(Msg)]) end,
    task_agents => TaskAgents,
    event_sink => event_sink(Stream, #{color => Color, render_markdown => RenderMarkdown})
  }.

-ifdef(TEST).
resolve_project_dir_for_test(Cwd0) ->
  resolve_project_dir(to_list(string:trim(to_bin(Cwd0)))).
-endif.

resolve_project_dir(Dir0) ->
  Dir = to_list(string:trim(to_bin(Dir0))),
  case Dir of
    "" -> Dir;
    _ -> resolve_project_dir_loop(Dir, 0)
  end.

resolve_project_dir_loop(Dir, Depth) when Depth >= 20 ->
  %% Safety valve: don't walk indefinitely.
  Dir;
resolve_project_dir_loop(Dir, Depth) ->
  DotEnv = filename:join([Dir, ".env"]),
  Rebar = filename:join([Dir, "rebar.config"]),
  case {filelib:is_file(DotEnv), filelib:is_file(Rebar)} of
    {true, _} ->
      Dir;
    {_, true} ->
      Dir;
    _ ->
      Parent = filename:dirname(Dir),
      case Parent =:= Dir of
        true -> Dir;
        false -> resolve_project_dir_loop(Parent, Depth + 1)
      end
  end.

ask_user_answerer(Question0) ->
  Q = ensure_map(Question0),
  Prompt = to_bin(maps:get(prompt, Q, maps:get(<<"prompt">>, Q, <<>>))),
  Choices0 = ensure_list(maps:get(choices, Q, maps:get(<<"choices">>, Q, []))),
  Choices = [to_bin(C) || C <- Choices0],
  io:format("~n~ts~n", [to_text(Prompt)]),
  case Choices of
    [] ->
      io:get_line("answer> ");
    _ ->
      lists:foreach(fun (C) -> io:format("  - ~ts~n", [to_text(C)]) end, Choices),
      Ans0 = io:get_line("answer> "),
      string:trim(to_bin(Ans0))
  end.

event_sink(Stream, Fmt0) ->
  Fmt = ensure_map(Fmt0),
  Color = to_bool_default(maps:get(color, Fmt, auto_color()), auto_color()),
  RenderMarkdown = to_bool_default(maps:get(render_markdown, Fmt, true), true),
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
            Txt2 = format_assistant_text(Txt, Color, RenderMarkdown),
            io:format(
              "~ts~n",
              [to_text(iolist_to_binary([ansi(<<"magenta">>, <<"assistant:">>, Color), <<" ">>, Txt2]))]
            )
        end;
      <<"tool.use">> ->
        maybe_break_delta(),
        Name = to_bin(maps:get(name, Ev, maps:get(<<"name">>, Ev, <<>>))),
        ToolUseId = to_bin(maps:get(tool_use_id, Ev, maps:get(<<"tool_use_id">>, Ev, <<>>))),
        Input = ensure_map(maps:get(input, Ev, maps:get(<<"input">>, Ev, #{}))),
        _ = remember_tool_name(ToolUseId, Name),
        Summary = tool_use_summary(Name, Input),
        Line = [ansi(<<"cyan">>, <<"tool.use">>, Color), <<" ">>, ansi(<<"cyan">>, Name, Color), format_cli_line(Summary, Color)],
        io:format("~ts~n", [to_text(iolist_to_binary(Line))]);
      <<"tool.result">> ->
        maybe_break_delta(),
        ToolUseId = to_bin(maps:get(tool_use_id, Ev, maps:get(<<"tool_use_id">>, Ev, <<>>))),
        ToolName = recall_tool_name(ToolUseId),
        IsError = maps:get(is_error, Ev, maps:get(<<"is_error">>, Ev, false)),
        case IsError of
          true ->
            Et = to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<"error">>))),
            Em = to_bin(maps:get(error_message, Ev, maps:get(<<"error_message">>, Ev, <<>>))),
            io:format(
              "~ts~n",
              [to_text(iolist_to_binary([ansi(<<"red">>, <<"tool.result ERROR">>, Color), <<" ">>, ansi(<<"red">>, Et, Color), <<": ">>, format_cli_line(Em, Color)]))]
            ),
            io:format("~n", []),
            maybe_forget_tool_name(ToolUseId);
          false ->
            Output = maps:get(output, Ev, maps:get(<<"output">>, Ev, undefined)),
            Lines = tool_result_lines(ToolName, Output),
            io:format("~ts~n", [to_text(ansi(<<"green">>, <<"tool.result ok">>, Color))]),
            lists:foreach(fun (L0) -> io:format("~ts~n", [to_text(format_cli_line(L0, Color))]) end, Lines),
            io:format("~n", []),
            maybe_forget_tool_name(ToolUseId)
        end;
      <<"runtime.error">> ->
        maybe_break_delta(),
        Phase = to_bin(maps:get(phase, Ev, maps:get(<<"phase">>, Ev, <<>>))),
        Et = to_bin(maps:get(error_type, Ev, maps:get(<<"error_type">>, Ev, <<>>))),
        io:format(
          "~ts~n~n",
          [to_text(iolist_to_binary([ansi(<<"red">>, <<"runtime.error">>, Color), <<" ">>, ansi(<<"red">>, Phase, Color), <<" ">>, ansi(<<"red">>, Et, Color)]))]
        );
      <<"result">> ->
        maybe_break_delta(),
        Stop = to_bin(maps:get(stop_reason, Ev, maps:get(<<"stop_reason">>, Ev, <<>>))),
        io:format(
          "~ts~n",
          [to_text(iolist_to_binary([ansi(<<"yellow">>, <<"result">>, Color), <<" stop_reason=">>, ansi(<<"yellow">>, Stop, Color)]))]
        );
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
parse_flags(["--api-key", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{api_key => to_bin(V)});
parse_flags(["--base-url", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{base_url => to_bin(V)});
parse_flags(["--api-key-header", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{api_key_header => to_bin(V)});
parse_flags(["--cwd", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{project_dir => to_bin(V)});
parse_flags(["--project-dir", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{project_dir => to_bin(V)});
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
parse_flags(["--color" | Rest], Acc) ->
  parse_flags(Rest, Acc#{color => true});
parse_flags(["--no-color" | Rest], Acc) ->
  parse_flags(Rest, Acc#{color => false});
parse_flags(["--render-markdown" | Rest], Acc) ->
  parse_flags(Rest, Acc#{render_markdown => true});
parse_flags(["--no-render-markdown" | Rest], Acc) ->
  parse_flags(Rest, Acc#{render_markdown => false});
parse_flags(["--openai-store", V0 | Rest], Acc) ->
  V = string:lowercase(string:trim(to_bin(V0))),
  Bool = V =/= <<"0">> andalso V =/= <<"false">> andalso V =/= <<"no">> andalso V =/= <<"off">>,
  parse_flags(Rest, Acc#{openai_store => Bool});
parse_flags(["--no-openai-store" | Rest], Acc) ->
  parse_flags(Rest, Acc#{openai_store => false});
parse_flags(["--max-steps", V0 | Rest], Acc) ->
  Max0 = parse_int(V0),
  Max =
    case Max0 of
      I when is_integer(I) -> clamp_int(I, 1, 200);
      _ -> 50
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
parse_flags(["--dsl", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{workflow_dsl => to_bin(V)});
parse_flags(["--workflow", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{workflow_dsl => to_bin(V)});
parse_flags(["--web-bind", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{web_bind => to_bin(V)});
parse_flags(["--web-port", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I > 0, I < 65536 ->
      parse_flags(Rest, Acc#{web_port => I});
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

cwd_safe() ->
  case file:get_cwd() of
    {ok, V} -> V;
    _ -> "."
  end.

first_non_blank([]) ->
  undefined;
first_non_blank([false | Rest]) ->
  %% os:getenv/1 returns the atom `false` when unset; treat as missing.
  first_non_blank(Rest);
first_non_blank([undefined | Rest]) ->
  first_non_blank(Rest);
first_non_blank([null | Rest]) ->
  first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V1 = strip_wrapping_quotes(to_bin(V0)),
  case byte_size(string:trim(V1)) > 0 of
    true -> string:trim(V1);
    false -> first_non_blank(Rest)
  end.

strip_wrapping_quotes(Val0) ->
  Val = string:trim(to_bin(Val0)),
  case byte_size(Val) >= 2 of
    false ->
      Val;
    true ->
      First = binary:at(Val, 0),
      Last = binary:at(Val, byte_size(Val) - 1),
      case {First, Last} of
        {$", $"} -> string:trim(binary:part(Val, 1, byte_size(Val) - 2));
        {$', $'} -> string:trim(binary:part(Val, 1, byte_size(Val) - 2));
        _ -> Val
      end
  end.

to_bool_default(undefined, Default) -> Default;
to_bool_default(null, Default) -> Default;
to_bool_default(true, _Default) -> true;
to_bool_default(false, _Default) -> false;
to_bool_default(1, _Default) -> true;
to_bool_default(0, _Default) -> false;
to_bool_default(V, Default) ->
  S = string:lowercase(string:trim(to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"allow">> -> true;
    <<"ok">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> [binary_to_list(B)];
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) ->
  %% Some callers provide UTF-8 bytes as a list of integers (iolist); others provide Unicode codepoints.
  %% Prefer treating lists as raw bytes when possible to avoid double-encoding ("è¿..." mojibake).
  try
    iolist_to_binary(L)
  catch
    _:_ -> unicode:characters_to_binary(L, utf8)
  end;
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_text(B) when is_binary(B) ->
  %% Decode UTF-8 bytes into Unicode codepoints for "~ts" formatting.
  try
    unicode:characters_to_list(B, utf8)
  catch
    _:_ -> binary_to_list(B)
  end;
to_text(L) when is_list(L) -> L;
to_text(A) when is_atom(A) -> atom_to_list(A);
to_text(Other) -> lists:flatten(io_lib:format("~p", [Other])).

remember_tool_name(ToolUseId0, Name0) ->
  ToolUseId = to_bin(ToolUseId0),
  Name = to_bin(Name0),
  case byte_size(string:trim(ToolUseId)) > 0 of
    true -> put({tool_name_by_id, ToolUseId}, Name);
    false -> ok
  end,
  ok.

recall_tool_name(ToolUseId0) ->
  ToolUseId = to_bin(ToolUseId0),
  case get({tool_name_by_id, ToolUseId}) of
    V when is_binary(V) -> V;
    _ -> <<>>
  end.

maybe_forget_tool_name(ToolUseId0) ->
  ToolUseId = to_bin(ToolUseId0),
  _ = erase({tool_name_by_id, ToolUseId}),
  ok.

tool_use_summary(<<"WebSearch">>, Input0) ->
  Input = ensure_map(Input0),
  Q =
    string:trim(
      to_bin(
        first_non_blank([
          maps:get(<<"query">>, Input, undefined),
          maps:get(query, Input, undefined),
          maps:get(<<"q">>, Input, undefined),
          maps:get(q, Input, undefined)
        ])
      )
    ),
  MR = maps:get(<<"max_results">>, Input, maps:get(max_results, Input, undefined)),
  Q2 = truncate_bin(Q, 120),
  case {byte_size(Q2) > 0, MR} of
    {true, undefined} -> iolist_to_binary([<<" q=\"">>, Q2, <<"\"">>]);
    {true, _} -> iolist_to_binary([<<" q=\"">>, Q2, <<"\" max_results=">>, to_bin(MR)]);
    _ -> <<>>
  end;
tool_use_summary(<<"WebFetch">>, Input0) ->
  Input = ensure_map(Input0),
  Url = string:trim(to_bin(maps:get(<<"url">>, Input, maps:get(url, Input, <<>>)))),
  Mode = string:trim(to_bin(maps:get(<<"mode">>, Input, maps:get(mode, Input, <<>>)))),
  Url2 = truncate_bin(Url, 160),
  Mode2 = truncate_bin(Mode, 40),
  case byte_size(Url2) > 0 of
    true ->
      case byte_size(Mode2) > 0 of
        true -> iolist_to_binary([<<" url=">>, Url2, <<" mode=">>, Mode2]);
        false -> iolist_to_binary([<<" url=">>, Url2])
      end;
    false -> <<>>
  end;
tool_use_summary(<<"Read">>, Input0) ->
  Input = ensure_map(Input0),
  P =
    string:trim(
      to_bin(
        first_non_blank([
          maps:get(<<"file_path">>, Input, undefined),
          maps:get(file_path, Input, undefined),
          maps:get(<<"filePath">>, Input, undefined),
          maps:get(filePath, Input, undefined),
          maps:get(<<"path">>, Input, undefined),
          maps:get(path, Input, undefined)
        ])
      )
    ),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<" file_path=">>, truncate_bin(P, 140)]); false -> <<>> end;
tool_use_summary(<<"List">>, Input0) ->
  Input = ensure_map(Input0),
  P =
    string:trim(
      to_bin(
        first_non_blank([
          maps:get(<<"path">>, Input, undefined),
          maps:get(path, Input, undefined),
          maps:get(<<"dir">>, Input, undefined),
          maps:get(dir, Input, undefined),
          maps:get(<<"directory">>, Input, undefined),
          maps:get(directory, Input, undefined)
        ])
      )
    ),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<" path=">>, truncate_bin(P, 140)]); false -> <<>> end;
tool_use_summary(<<"Glob">>, Input0) ->
  Input = ensure_map(Input0),
  Pattern = string:trim(to_bin(maps:get(<<"pattern">>, Input, maps:get(pattern, Input, <<>>)))),
  Root = string:trim(to_bin(first_non_blank([maps:get(<<"root">>, Input, undefined), maps:get(root, Input, undefined), maps:get(<<"path">>, Input, undefined), maps:get(path, Input, undefined)]))),
  P2 = safe_preview(Pattern, 140),
  R2 = safe_preview(Root, 140),
  case {byte_size(P2) > 0, byte_size(R2) > 0} of
    {true, true} -> iolist_to_binary([<<" pattern=\"">>, P2, <<"\" root=">>, R2]);
    {true, false} -> iolist_to_binary([<<" pattern=\"">>, P2, <<"\"">>]);
    _ -> <<>>
  end;
tool_use_summary(<<"Grep">>, Input0) ->
  Input = ensure_map(Input0),
  Query = string:trim(to_bin(maps:get(<<"query">>, Input, maps:get(query, Input, <<>>)))),
  Root = string:trim(to_bin(first_non_blank([maps:get(<<"root">>, Input, undefined), maps:get(root, Input, undefined), maps:get(<<"path">>, Input, undefined), maps:get(path, Input, undefined)]))),
  FileGlob = string:trim(to_bin(maps:get(<<"file_glob">>, Input, maps:get(file_glob, Input, <<>>)))),
  Mode = string:trim(to_bin(maps:get(<<"mode">>, Input, maps:get(mode, Input, <<>>)))),
  Q2 = safe_preview(Query, 120),
  R2 = safe_preview(Root, 140),
  G2 = safe_preview(FileGlob, 80),
  M2 = safe_preview(Mode, 40),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Q2) > 0 -> iolist_to_binary([<<" q=\"">>, Q2, <<"\"">>]); true -> <<>> end,
        if byte_size(R2) > 0 -> iolist_to_binary([<<" root=">>, R2]); true -> <<>> end,
        if byte_size(G2) > 0 -> iolist_to_binary([<<" file_glob=">>, G2]); true -> <<>> end,
        if byte_size(M2) > 0 -> iolist_to_binary([<<" mode=">>, M2]); true -> <<>> end
      ]
    )
  );
tool_use_summary(<<"Skill">>, Input0) ->
  Input = ensure_map(Input0),
  Name =
    string:trim(
      to_bin(
        first_non_blank([
          maps:get(<<"name">>, Input, undefined),
          maps:get(name, Input, undefined),
          maps:get(<<"skill">>, Input, undefined),
          maps:get(skill, Input, undefined)
        ])
      )
    ),
  case byte_size(Name) > 0 of
    true -> iolist_to_binary([<<" name=">>, safe_preview(Name, 80)]);
    false -> <<>>
  end;
tool_use_summary(<<"SlashCommand">>, Input0) ->
  Input = ensure_map(Input0),
  Name = string:trim(to_bin(maps:get(<<"name">>, Input, maps:get(name, Input, <<>>)))),
  Args = to_bin(maps:get(<<"args">>, Input, maps:get(args, Input, maps:get(<<"arguments">>, Input, maps:get(arguments, Input, <<>>))))),
  N2 = safe_preview(Name, 80),
  A2 = safe_preview(string:trim(Args), 160),
  case {byte_size(N2) > 0, byte_size(A2) > 0} of
    {true, true} -> iolist_to_binary([<<" name=">>, N2, <<" args=\"">>, A2, <<"\"">>]);
    {true, false} -> iolist_to_binary([<<" name=">>, N2]);
    _ -> <<>>
  end;
tool_use_summary(<<"Write">>, Input0) ->
  Input = ensure_map(Input0),
  FilePath = string:trim(to_bin(first_non_blank([maps:get(<<"file_path">>, Input, undefined), maps:get(file_path, Input, undefined), maps:get(<<"filePath">>, Input, undefined), maps:get(filePath, Input, undefined)]))),
  Overwrite = maps:get(<<"overwrite">>, Input, maps:get(overwrite, Input, undefined)),
  Content0 = maps:get(<<"content">>, Input, maps:get(content, Input, undefined)),
  Bytes =
    case Content0 of
      B when is_binary(B) -> byte_size(B);
      L when is_list(L) -> byte_size(to_bin(L));
      _ -> undefined
    end,
  P2 = safe_preview(FilePath, 160),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(P2) > 0 -> iolist_to_binary([<<" file_path=">>, P2]); true -> <<>> end,
        case Bytes of undefined -> <<>>; _ -> iolist_to_binary([<<" bytes=">>, integer_to_binary(Bytes)]) end,
        case Overwrite of undefined -> <<>>; _ -> iolist_to_binary([<<" overwrite=">>, to_bin(Overwrite)]) end
      ]
    )
  );
tool_use_summary(<<"Edit">>, Input0) ->
  Input = ensure_map(Input0),
  FilePath = string:trim(to_bin(first_non_blank([maps:get(<<"file_path">>, Input, undefined), maps:get(file_path, Input, undefined), maps:get(<<"filePath">>, Input, undefined), maps:get(filePath, Input, undefined)]))),
  Count = maps:get(<<"count">>, Input, maps:get(count, Input, undefined)),
  ReplaceAll = maps:get(<<"replace_all">>, Input, maps:get(replace_all, Input, maps:get(<<"replaceAll">>, Input, maps:get(replaceAll, Input, undefined)))),
  P2 = safe_preview(FilePath, 160),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(P2) > 0 -> iolist_to_binary([<<" file_path=">>, P2]); true -> <<>> end,
        case Count of undefined -> <<>>; _ -> iolist_to_binary([<<" count=">>, to_bin(Count)]) end,
        case ReplaceAll of undefined -> <<>>; _ -> iolist_to_binary([<<" replace_all=">>, to_bin(ReplaceAll)]) end
      ]
    )
  );
tool_use_summary(<<"Bash">>, Input0) ->
  Input = ensure_map(Input0),
  Cmd0 = string:trim(to_bin(maps:get(<<"command">>, Input, maps:get(command, Input, <<>>)))),
  Workdir = string:trim(to_bin(maps:get(<<"workdir">>, Input, maps:get(workdir, Input, <<>>)))),
  Timeout = maps:get(<<"timeout_ms">>, Input, maps:get(timeout_ms, Input, maps:get(<<"timeout">>, Input, maps:get(timeout, Input, undefined)))),
  Cmd = safe_preview(redact_secrets(Cmd0), 220),
  Wd = safe_preview(Workdir, 120),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Cmd) > 0 -> iolist_to_binary([<<" command=\"">>, Cmd, <<"\"">>]); true -> <<>> end,
        if byte_size(Wd) > 0 -> iolist_to_binary([<<" workdir=">>, Wd]); true -> <<>> end,
        case Timeout of undefined -> <<>>; _ -> iolist_to_binary([<<" timeout=">>, to_bin(Timeout)]) end
      ]
    )
  );
tool_use_summary(<<"NotebookEdit">>, Input0) ->
  Input = ensure_map(Input0),
  Nb = string:trim(to_bin(maps:get(<<"notebook_path">>, Input, maps:get(notebook_path, Input, <<>>)))),
  Mode = string:trim(to_bin(maps:get(<<"edit_mode">>, Input, maps:get(edit_mode, Input, <<>>)))),
  Cell = string:trim(to_bin(maps:get(<<"cell_id">>, Input, maps:get(cell_id, Input, <<>>)))),
  N2 = safe_preview(Nb, 160),
  M2 = safe_preview(Mode, 40),
  C2 = safe_preview(Cell, 80),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(N2) > 0 -> iolist_to_binary([<<" notebook_path=">>, N2]); true -> <<>> end,
        if byte_size(M2) > 0 -> iolist_to_binary([<<" edit_mode=">>, M2]); true -> <<>> end,
        if byte_size(C2) > 0 -> iolist_to_binary([<<" cell_id=">>, C2]); true -> <<>> end
      ]
    )
  );
tool_use_summary(<<"lsp">>, Input0) ->
  Input = ensure_map(Input0),
  Op = string:trim(to_bin(maps:get(<<"operation">>, Input, maps:get(operation, Input, <<>>)))),
  File =
    string:trim(
      to_bin(
        first_non_blank([
          maps:get(<<"filePath">>, Input, undefined),
          maps:get(filePath, Input, undefined),
          maps:get(<<"file_path">>, Input, undefined),
          maps:get(file_path, Input, undefined)
        ])
      )
    ),
  Line = maps:get(<<"line">>, Input, maps:get(line, Input, undefined)),
  Ch = maps:get(<<"character">>, Input, maps:get(character, Input, undefined)),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Op) > 0 -> iolist_to_binary([<<" operation=">>, safe_preview(Op, 60)]); true -> <<>> end,
        if byte_size(File) > 0 -> iolist_to_binary([<<" file=">>, safe_preview(File, 160)]); true -> <<>> end,
        case {Line, Ch} of
          {undefined, _} -> <<>>;
          {_, undefined} -> iolist_to_binary([<<" line=">>, to_bin(Line)]);
          _ -> iolist_to_binary([<<" pos=">>, to_bin(Line), <<":">>, to_bin(Ch)])
        end
      ]
    )
  );
tool_use_summary(<<"TodoWrite">>, Input0) ->
  Input = ensure_map(Input0),
  Todos = maps:get(<<"todos">>, Input, maps:get(todos, Input, [])),
  case is_list(Todos) of
    true -> iolist_to_binary([<<" todos=">>, integer_to_binary(length(Todos))]);
    false -> <<>>
  end;
tool_use_summary(<<"Task">>, Input0) ->
  Input = ensure_map(Input0),
  Agent = string:trim(to_bin(maps:get(<<"agent">>, Input, maps:get(agent, Input, <<>>)))),
  Prompt = string:trim(to_bin(maps:get(<<"prompt">>, Input, maps:get(prompt, Input, <<>>)))),
  A2 = safe_preview(Agent, 40),
  P2 = safe_preview(redact_secrets(Prompt), 140),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(A2) > 0 -> iolist_to_binary([<<" agent=">>, A2]); true -> <<>> end,
        if byte_size(P2) > 0 -> iolist_to_binary([<<" prompt=\"">>, P2, <<"\"">>]); true -> <<>> end
      ]
    )
  );
tool_use_summary(_Other, _Input) ->
  <<>>.

tool_result_lines(<<"WebSearch">>, Output0) ->
  Output = ensure_map(Output0),
  Total = maps:get(total_results, Output, maps:get(<<"total_results">>, Output, undefined)),
  Results0 = maps:get(results, Output, maps:get(<<"results">>, Output, [])),
  Results = ensure_list(Results0),
  Head =
    case Total of
      undefined -> <<"WebSearch results">>;
      _ -> iolist_to_binary([<<"WebSearch results total=">>, to_bin(Total)])
    end,
  Items =
    lists:sublist(
      [
        websearch_result_line(R)
      ||
        R0 <- Results,
        R <- [ensure_map(R0)],
        byte_size(string:trim(to_bin(maps:get(url, R, maps:get(<<"url">>, R, <<>>))))) > 0
      ],
      3
    ),
  [Head | Items];
tool_result_lines(<<"WebFetch">>, Output0) ->
  Output = ensure_map(Output0),
  Status = maps:get(status, Output, maps:get(<<"status">>, Output, undefined)),
  Url = maps:get(url, Output, maps:get(<<"url">>, Output, maps:get(final_url, Output, maps:get(<<"final_url">>, Output, <<>>)))),
  Title = maps:get(title, Output, maps:get(<<"title">>, Output, <<>>)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  Line1 =
    iolist_to_binary([
      <<"WebFetch">>,
      case Status of undefined -> <<>>; _ -> iolist_to_binary([<<" status=">>, to_bin(Status)]) end,
      case byte_size(string:trim(to_bin(Tr))) > 0 of false -> <<>>; true -> iolist_to_binary([<<" truncated=">>, to_bin(Tr)]) end
    ]),
  Line2 =
    case byte_size(string:trim(to_bin(Url))) > 0 of
      true -> iolist_to_binary([<<"url=">>, truncate_bin(to_bin(Url), 200)]);
      false -> <<>>
    end,
  Line3 =
    case byte_size(string:trim(to_bin(Title))) > 0 of
      true -> iolist_to_binary([<<"title=">>, truncate_bin(to_bin(Title), 200)]);
      false -> <<>>
    end,
  [L || L <- [Line1, Line2, Line3], byte_size(string:trim(to_bin(L))) > 0];
tool_result_lines(<<"List">>, Output0) ->
  Output = ensure_map(Output0),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  Count = maps:get(count, Output, maps:get(<<"count">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"List path=">>, safe_preview(to_bin(Path), 200)]),
    iolist_to_binary([<<"count=">>, to_bin(Count), <<" truncated=">>, to_bin(Tr)])
  ];
tool_result_lines(<<"Read">>, Output0) ->
  Output = ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  Total = maps:get(total_lines, Output, maps:get(<<"total_lines">>, Output, undefined)),
  Returned = maps:get(lines_returned, Output, maps:get(<<"lines_returned">>, Output, undefined)),
  Bytes = maps:get(bytes_returned, Output, maps:get(<<"bytes_returned">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Read file_path=">>, safe_preview(to_bin(Path), 220)]),
    iolist_to_binary([<<"bytes_returned=">>, to_bin(Bytes), <<" lines_returned=">>, to_bin(Returned), <<" total_lines=">>, to_bin(Total), <<" truncated=">>, to_bin(Tr)])
  ];
tool_result_lines(<<"Glob">>, Output0) ->
  Output = ensure_map(Output0),
  Pattern = maps:get(pattern, Output, maps:get(<<"pattern">>, Output, <<>>)),
  Root = maps:get(root, Output, maps:get(<<"root">>, Output, <<>>)),
  Count = maps:get(count, Output, maps:get(<<"count">>, Output, undefined)),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Glob pattern=\"">>, safe_preview(to_bin(Pattern), 140), <<"\" root=">>, safe_preview(to_bin(Root), 220)]),
    iolist_to_binary([<<"count=">>, to_bin(Count), <<" truncated=">>, to_bin(Tr)])
  ];
tool_result_lines(<<"Grep">>, Output0) ->
  Output = ensure_map(Output0),
  Root = maps:get(root, Output, maps:get(<<"root">>, Output, <<>>)),
  Query = maps:get(query, Output, maps:get(<<"query">>, Output, <<>>)),
  Total = maps:get(total_matches, Output, maps:get(<<"total_matches">>, Output, maps:get(count, Output, maps:get(<<"count">>, Output, undefined)))),
  Tr = maps:get(truncated, Output, maps:get(<<"truncated">>, Output, undefined)),
  [
    iolist_to_binary([<<"Grep root=">>, safe_preview(to_bin(Root), 220)]),
    iolist_to_binary([<<"query=\"">>, safe_preview(to_bin(Query), 120), <<"\" total=">>, to_bin(Total), <<" truncated=">>, to_bin(Tr)])
  ];
tool_result_lines(<<"Skill">>, Output0) ->
  Output = ensure_map(Output0),
  Name = maps:get(name, Output, maps:get(<<"name">>, Output, <<>>)),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  [iolist_to_binary([<<"Skill name=">>, safe_preview(to_bin(Name), 80), <<" path=">>, safe_preview(to_bin(Path), 220)])];
tool_result_lines(<<"SlashCommand">>, Output0) ->
  Output = ensure_map(Output0),
  Name = maps:get(name, Output, maps:get(<<"name">>, Output, <<>>)),
  Path = maps:get(path, Output, maps:get(<<"path">>, Output, <<>>)),
  [iolist_to_binary([<<"SlashCommand name=">>, safe_preview(to_bin(Name), 80), <<" path=">>, safe_preview(to_bin(Path), 220)])];
tool_result_lines(<<"Write">>, Output0) ->
  Output = ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  Bytes = maps:get(bytes_written, Output, maps:get(<<"bytes_written">>, Output, undefined)),
  [iolist_to_binary([<<"Write file_path=">>, safe_preview(to_bin(Path), 220), <<" bytes_written=">>, to_bin(Bytes)])];
tool_result_lines(<<"Edit">>, Output0) ->
  Output = ensure_map(Output0),
  Path = maps:get(file_path, Output, maps:get(<<"file_path">>, Output, <<>>)),
  R = maps:get(replacements, Output, maps:get(<<"replacements">>, Output, undefined)),
  [iolist_to_binary([<<"Edit file_path=">>, safe_preview(to_bin(Path), 220), <<" replacements=">>, to_bin(R)])];
tool_result_lines(<<"Bash">>, Output0) ->
  Output = ensure_map(Output0),
  Exit = maps:get(exit_code, Output, maps:get(<<"exit_code">>, Output, maps:get(exitCode, Output, maps:get(<<"exitCode">>, Output, undefined)))),
  Killed = maps:get(killed, Output, maps:get(<<"killed">>, Output, undefined)),
  Full = maps:get(full_output_file_path, Output, maps:get(<<"full_output_file_path">>, Output, undefined)),
  [
    iolist_to_binary([<<"Bash exit_code=">>, to_bin(Exit), <<" killed=">>, to_bin(Killed)]),
    case Full of null -> <<>>; undefined -> <<>>; <<>> -> <<>>; "" -> <<>>; _ -> iolist_to_binary([<<"full_output_file_path=">>, safe_preview(to_bin(Full), 260)]) end
  ];
tool_result_lines(<<"NotebookEdit">>, Output0) ->
  Output = ensure_map(Output0),
  Msg = maps:get(message, Output, maps:get(<<"message">>, Output, <<>>)),
  Type = maps:get(edit_type, Output, maps:get(<<"edit_type">>, Output, <<>>)),
  Cell = maps:get(cell_id, Output, maps:get(<<"cell_id">>, Output, <<>>)),
  Total = maps:get(total_cells, Output, maps:get(<<"total_cells">>, Output, undefined)),
  [
    iolist_to_binary([<<"NotebookEdit ">>, safe_preview(to_bin(Msg), 80), <<" edit_type=">>, safe_preview(to_bin(Type), 30)]),
    iolist_to_binary([<<"cell_id=">>, safe_preview(to_bin(Cell), 80), <<" total_cells=">>, to_bin(Total)])
  ];
tool_result_lines(<<"lsp">>, Output0) ->
  Output = ensure_map(Output0),
  Title = maps:get(title, Output, maps:get(<<"title">>, Output, <<>>)),
  [iolist_to_binary([<<"lsp ">>, safe_preview(to_bin(Title), 260)])];
tool_result_lines(<<"TodoWrite">>, Output0) ->
  Output = ensure_map(Output0),
  Stats = ensure_map(maps:get(stats, Output, maps:get(<<"stats">>, Output, #{}))),
  Total = maps:get(total, Stats, maps:get(<<"total">>, Stats, undefined)),
  IP = maps:get(in_progress, Stats, maps:get(<<"in_progress">>, Stats, undefined)),
  P = maps:get(pending, Stats, maps:get(<<"pending">>, Stats, undefined)),
  C = maps:get(completed, Stats, maps:get(<<"completed">>, Stats, undefined)),
  X = maps:get(cancelled, Stats, maps:get(<<"cancelled">>, Stats, undefined)),
  [iolist_to_binary([<<"TodoWrite total=">>, to_bin(Total), <<" pending=">>, to_bin(P), <<" in_progress=">>, to_bin(IP), <<" completed=">>, to_bin(C), <<" cancelled=">>, to_bin(X)])];
tool_result_lines(_, _Output) ->
  [].

websearch_result_line(R0) ->
  R = ensure_map(R0),
  Title0 = maps:get(title, R, maps:get(<<"title">>, R, <<>>)),
  Url0 = maps:get(url, R, maps:get(<<"url">>, R, <<>>)),
  Title = truncate_bin(string:trim(to_bin(Title0)), 120),
  Url = truncate_bin(string:trim(to_bin(Url0)), 200),
  case byte_size(Title) > 0 of
    true -> iolist_to_binary([<<"- ">>, Title, <<" (">>, Url, <<")">>]);
    false -> iolist_to_binary([<<"- ">>, Url])
  end.

truncate_bin(Bin0, Max) when is_integer(Max), Max > 0 ->
  Bin = to_bin(Bin0),
  case byte_size(Bin) > Max of
    true -> <<(binary:part(Bin, 0, Max))/binary, "...">>;
    false -> Bin
  end.

safe_preview(Bin0, Max) ->
  truncate_bin(redact_secrets(to_bin(Bin0)), Max).

redact_secrets(Bin0) ->
  Bin = to_bin(Bin0),
  %% Best-effort redaction for common secret shapes. Keep it conservative.
  B1 = re_replace(Bin, <<"(sk-[A-Za-z0-9]{10,})">>, <<"sk-***">>),
  B2 = re_replace(B1, <<"(?i)bearer\\s+[A-Za-z0-9\\-\\._~\\+\\/]+=*">>, <<"Bearer ***">>),
  B3 = re_replace(B2, <<"(?i)(OPENAI_API_KEY|TAVILY_API_KEY)\\s*[:=]\\s*[^\\s\\\"\\']+">>, <<"$1=***">>),
  B4 = re_replace(B3, <<"(?i)(x-api-key|x_api_key|api_key)\\s*[:=]\\s*[^\\s\\\"\\']+">>, <<"$1=***">>),
  B4.

re_replace(Bin, Pattern, Replace) ->
  try
    re:replace(Bin, Pattern, Replace, [global, {return, binary}])
  catch
    _:_ -> Bin
  end.

%% --- Terminal formatting helpers (best-effort; safe to disable via --no-color / NO_COLOR) ---

auto_color() ->
  %% Follow https://no-color.org/ : if NO_COLOR is set (any value), disable ANSI.
  case os:getenv("NO_COLOR") of
    false ->
      case os:getenv("OPENAGENTIC_NO_COLOR") of
        false ->
          case os:getenv("TERM") of
            "dumb" -> false;
            _ -> true
          end;
        _ ->
          false
      end;
    _ ->
      false
  end.

ansi_reset() -> <<"\033[0m">>.

ansi_seq(<<"red">>) -> <<"\033[31m">>;
ansi_seq(<<"green">>) -> <<"\033[32m">>;
ansi_seq(<<"yellow">>) -> <<"\033[33m">>;
ansi_seq(<<"blue">>) -> <<"\033[34m">>;
ansi_seq(<<"magenta">>) -> <<"\033[35m">>;
ansi_seq(<<"cyan">>) -> <<"\033[36m">>;
ansi_seq(<<"dim">>) -> <<"\033[2m">>;
ansi_seq(<<"bold">>) -> <<"\033[1m">>;
ansi_seq(<<"underline">>) -> <<"\033[4m">>;
ansi_seq(<<"blue_under">>) -> <<"\033[34m\033[4m">>;
ansi_seq(_) -> <<>>.

ansi(Style0, Text0, Enabled) ->
  case Enabled of
    true ->
      Style = to_bin(Style0),
      Text = to_bin(Text0),
      [ansi_seq(Style), Text, ansi_reset()];
    false ->
      to_bin(Text0)
  end.

format_cli_line(Line0, Color) ->
  Bin0 = redact_secrets(to_bin(Line0)),
  Bin = normalize_newlines(Bin0),
  highlight_common(Bin, Color).

format_assistant_text(Txt0, Color, RenderMarkdown) ->
  Txt1 = redact_secrets(to_bin(Txt0)),
  Txt = normalize_newlines(Txt1),
  case RenderMarkdown of
    true -> render_markdown(Txt, Color);
    false -> highlight_common(Txt, Color)
  end.

normalize_newlines(Bin0) ->
  Bin = to_bin(Bin0),
  re_replace(Bin, <<"\r\n">>, <<"\n">>).

highlight_common(Bin0, false) ->
  to_bin(Bin0);
highlight_common(Bin0, true) ->
  Bin = to_bin(Bin0),
  %% highlight URLs, quoted commands, and common filesystem paths/kv pairs.
  B1 = highlight_quoted_kv(Bin),
  B2 = highlight_urls(B1),
  B3 = highlight_paths(B2),
  B4 = highlight_inline_code(B3),
  B4.

highlight_urls(Bin0) ->
  UrlStyle = ansi_seq(<<"blue_under">>),
  Reset = ansi_reset(),
  %% keep it conservative: stop at whitespace or common closing delimiters
  Pattern = <<"(https?://[^\\s\\)\\]}>\\\"\\']+)">>,
  Replace = iolist_to_binary([UrlStyle, <<"\\1">>, Reset]),
  re_replace(Bin0, Pattern, Replace).

highlight_paths(Bin0) ->
  Blue = ansi_seq(<<"blue">>),
  Reset = ansi_reset(),
  %% Windows drive paths: E:\foo or e:/foo
  P1 = <<"(?i)([a-z]:[\\\\/][^\\s\\)\\]}>\\\"\\']+)">>,
  R1 = iolist_to_binary([Blue, <<"\\1">>, Reset]),
  B1 = re_replace(Bin0, P1, R1),
  %% Relative paths: ./foo or .\foo
  P2 = <<"(\\./[^\\s\\)\\]}>\\\"\\']+|\\.\\\\[^\\s\\)\\]}>\\\"\\']+)">>,
  R2 = iolist_to_binary([Blue, <<"\\1">>, Reset]),
  re_replace(B1, P2, R2).

highlight_quoted_kv(Bin0) ->
  Yellow = ansi_seq(<<"yellow">>),
  Reset = ansi_reset(),
  %% command="...": highlight the inside
  P1 = <<"command=\\\"([^\\\"]+)\\\"">>,
  R1 = iolist_to_binary([<<"command=\\\"">>, Yellow, <<"\\1">>, Reset, <<"\\\"">>]),
  B1 = re_replace(Bin0, P1, R1),
  %% file_path=/path or workdir=...: highlight value part
  P2 = <<"(?i)\\b(file_path|path|root|workdir|url)=(\\S+)">>,
  R2 = iolist_to_binary([<<"\\1=">>, Yellow, <<"\\2">>, Reset]),
  re_replace(B1, P2, R2).

highlight_inline_code(Bin0) ->
  Yellow = ansi_seq(<<"yellow">>),
  Reset = ansi_reset(),
  %% inline `code`
  P = <<"`([^`\\n]+)`">>,
  R = iolist_to_binary([Yellow, <<"`\\1`">>, Reset]),
  re_replace(Bin0, P, R).

render_markdown(Text0, Color) ->
  Text = to_bin(Text0),
  Lines = binary:split(Text, <<"\n">>, [global]),
  {OutLines, _} = render_markdown_lines(Lines, Color, false, []),
  iolist_to_binary(lists:join(<<"\n">>, lists:reverse(OutLines))).

render_markdown_lines([], _Color, InCode, Acc) ->
  {Acc, InCode};
render_markdown_lines([Line0 | Rest], Color, InCode0, Acc0) ->
  Line = to_bin(Line0),
  Trim = string:trim(Line),
  case starts_with(Trim, <<"```">>) of
    true ->
      %% show fence dim and toggle code mode
      L2 = iolist_to_binary(ansi(<<"dim">>, Line, Color)),
      render_markdown_lines(Rest, Color, not InCode0, [L2 | Acc0]);
    false when InCode0 =:= true ->
      L2 = iolist_to_binary(ansi(<<"yellow">>, Line, Color)),
      render_markdown_lines(Rest, Color, InCode0, [L2 | Acc0]);
    false ->
      L2 = render_markdown_line(Line, Color),
      render_markdown_lines(Rest, Color, InCode0, [L2 | Acc0])
  end.

render_markdown_line(Line0, Color) ->
  Line = to_bin(Line0),
  case Line of
    <<$#, _/binary>> ->
      iolist_to_binary(ansi(<<"bold">>, highlight_common(Line, Color), Color));
    <<"- ", Rest/binary>> ->
      iolist_to_binary([ansi(<<"dim">>, <<"-">>, Color), <<" ">>, highlight_common(Rest, Color)]);
    <<"* ", Rest/binary>> ->
      iolist_to_binary([ansi(<<"dim">>, <<"*">>, Color), <<" ">>, highlight_common(Rest, Color)]);
    _ ->
      highlight_common(Line, Color)
  end.

starts_with(Bin, Prefix) when is_binary(Bin), is_binary(Prefix) ->
  Sz = byte_size(Prefix),
  case byte_size(Bin) >= Sz of
    true -> binary:part(Bin, 0, Sz) =:= Prefix;
    false -> false
  end.
