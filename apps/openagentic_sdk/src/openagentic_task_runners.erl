-module(openagentic_task_runners).

-export([
  compose/1,
  built_in_explore/1
]).

%% Compose multiple task runners.
%%
%% Each runner is a fun(Agent, Prompt, TaskCtx) -> Output.
%% To delegate "not my agent" to the next runner, a runner should throw:
%%   erlang:error({unhandled_agent, Agent}).
compose(Runners0) ->
  Runners = ensure_list(Runners0),
  fun (Agent0, Prompt0, Ctx0) ->
    Agent = to_bin(Agent0),
    Prompt = to_bin(Prompt0),
    Ctx = ensure_map(Ctx0),
    compose_loop(Runners, Agent, Prompt, Ctx, undefined)
  end.

compose_loop([], _Agent, _Prompt, _Ctx, LastUnhandled) ->
  case LastUnhandled of
    undefined -> erlang:error({unhandled_agent, <<"">>});
    _ -> erlang:error(LastUnhandled)
  end;
compose_loop([R | Rest], Agent, Prompt, Ctx, _LastUnhandled) ->
  try
    R(Agent, Prompt, Ctx)
  catch
    error:{unhandled_agent, _} = E ->
      compose_loop(Rest, Agent, Prompt, Ctx, E);
    throw:{unhandled_agent, _} = E2 ->
      compose_loop(Rest, Agent, Prompt, Ctx, E2)
  end.

%% Built-in explore subagent runner (Kotlin parity).
built_in_explore(BaseOpts0) ->
  BaseOpts = ensure_map(BaseOpts0),
  AllowedTools = [<<"Read">>, <<"List">>, <<"Glob">>, <<"Grep">>],
  ToolMods = [openagentic_tool_read, openagentic_tool_list, openagentic_tool_glob, openagentic_tool_grep],
  SystemPrompt = openagentic_built_in_subagents:explore_system_prompt(),
  MaxSteps = maps:get(subagent_max_steps, BaseOpts, maps:get(subagentMaxSteps, BaseOpts, 25)),
  fun (Agent0, Prompt0, TaskCtx0) ->
    Agent = string:lowercase(string:trim(to_bin(Agent0))),
    case Agent of
      <<"explore">> -> ok;
      _ -> erlang:error({unhandled_agent, Agent})
    end,
    Prompt = string:trim(to_bin(Prompt0)),
    TaskCtx = ensure_map(TaskCtx0),
    ParentSessionId = to_bin(maps:get(session_id, TaskCtx, <<>>)),
    ParentToolUseId = to_bin(maps:get(tool_use_id, TaskCtx, <<>>)),
    Emit = maps:get(emit_progress, TaskCtx, undefined),
    _ = maybe_emit(Emit, <<"子任务(explore)：启动">>),

    %% Build subquery options (fresh context).
    SubOpts0 =
      maps:merge(
        BaseOpts,
        #{
          tools => ToolMods,
          allowed_tools => AllowedTools,
          permission_gate => openagentic_permissions:bypass(),
          task_runner => undefined,
          task_agents => [],
          resume_session_id => undefined,
          resumeSessionId => undefined,
          include_partial_messages => false,
          max_steps => MaxSteps,
          system_prompt => SystemPrompt
        }
      ),
    SubOpts = SubOpts0#{event_sink => sub_event_sink(Emit)},
    case openagentic_runtime:query(Prompt, SubOpts) of
      {ok, #{session_id := SubSessionId0, final_text := FinalText0}} ->
        SubSessionId = to_bin(SubSessionId0),
        Answer = string:trim(to_bin(FinalText0)),
        #{
          <<"ok">> => true,
          <<"agent">> => Agent,
          <<"parent_session_id">> => ParentSessionId,
          <<"parent_tool_use_id">> => ParentToolUseId,
          <<"sub_session_id">> => SubSessionId,
          <<"answer">> => Answer
        };
      {error, Reason} ->
        _ = maybe_emit(Emit, <<"子任务(explore)：运行错误">>),
        erlang:error({explore_task_failed, Reason})
    end
  end.

sub_event_sink(Emit) ->
  fun (Event0) ->
    case Emit of
      F when is_function(F, 1) ->
        Event = ensure_map(Event0),
        Type = to_bin(maps:get(type, Event, maps:get(<<"type">>, Event, <<>>))),
        case Type of
          <<"tool.use">> ->
            Name = to_bin(maps:get(name, Event, maps:get(<<"name">>, Event, <<>>))),
            Input = ensure_map(maps:get(input, Event, maps:get(<<"input">>, Event, #{}))),
            F(iolist_to_binary([<<"子任务(explore)：">>, humanize_tool_use(Name, Input)]));
          <<"tool.result">> ->
            IsError = maps:get(is_error, Event, maps:get(<<"is_error">>, Event, false)),
            case IsError of
              true ->
                Et = to_bin(maps:get(error_type, Event, maps:get(<<"error_type">>, Event, <<"error">>))),
                F(iolist_to_binary([<<"子任务(explore)：工具失败 ">>, Et]));
              false -> ok
            end;
          <<"runtime.error">> ->
            Et = to_bin(maps:get(error_type, Event, maps:get(<<"error_type">>, Event, <<"RuntimeError">>))),
            F(iolist_to_binary([<<"子任务(explore)：运行错误 ">>, Et]));
          _ ->
            ok
        end;
      _ ->
        ok
    end
  end.

humanize_tool_use(<<"Read">>, Input) ->
  P0 = first_non_empty(Input, [<<"file_path">>, <<"filePath">>, file_path, filePath]),
  P = tail(P0, 60),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<"读取文件：">>, P]); false -> <<"读取文件">> end;
humanize_tool_use(<<"List">>, Input) ->
  P0 = first_non_empty(Input, [<<"path">>, path, <<"dir">>, dir, <<"directory">>, directory]),
  P = tail(P0, 60),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<"列目录：">>, P]); false -> <<"列目录">> end;
humanize_tool_use(<<"Glob">>, Input) ->
  P0 = first_non_empty(Input, [<<"pattern">>, pattern]),
  P = head(P0, 60),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<"匹配文件：">>, P]); false -> <<"匹配文件">> end;
humanize_tool_use(<<"Grep">>, Input) ->
  P0 = first_non_empty(Input, [<<"pattern">>, pattern, <<"query">>, query]),
  P = head(P0, 40),
  case byte_size(P) > 0 of true -> iolist_to_binary([<<"搜索文本：">>, P]); false -> <<"搜索文本">> end;
humanize_tool_use(Name0, _Input) ->
  Name = string:trim(to_bin(Name0)),
  case byte_size(Name) > 0 of true -> Name; false -> <<"工具调用">> end.

maybe_emit(F, Msg) when is_function(F, 1) ->
  try F(Msg) catch _:_ -> ok end;
maybe_emit(_, _) ->
  ok.

head(undefined, _N) -> <<>>;
head(null, _N) -> <<>>;
head(B0, N0) ->
  B = string:trim(to_bin(B0)),
  N = erlang:max(0, N0),
  case byte_size(B) =< N of
    true -> B;
    false -> binary:part(B, 0, N)
  end.

tail(undefined, _N) -> <<>>;
tail(null, _N) -> <<>>;
tail(B0, N0) ->
  B = string:trim(to_bin(B0)),
  N = erlang:max(0, N0),
  Sz = byte_size(B),
  case Sz =< N of
    true -> B;
    false -> binary:part(B, Sz - N, N)
  end.

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

