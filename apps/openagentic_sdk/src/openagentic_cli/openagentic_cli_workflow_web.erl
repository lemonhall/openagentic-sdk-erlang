-module(openagentic_cli_workflow_web).
-export([workflow_cmd/1,web_cmd/1,start_web_runtime_unlinked/1]).

workflow_cmd(Args0) ->
  {Flags, Pos} = openagentic_cli_flags:parse_flags(Args0, #{}),
  Prompt0 = string:trim(iolist_to_binary(lists:join(" ", Pos))),
  case byte_size(Prompt0) > 0 of
    false ->
      io:format("Missing prompt.~n~n", []),
      openagentic_cli_main:usage(),
      halt(2);
    true ->
      Dsl0 = maps:get(workflow_dsl, Flags, maps:get(workflowDsl, Flags, undefined)),
      Dsl1 = string:trim(openagentic_cli_values:to_bin(Dsl0)),
      Dsl =
        case Dsl1 of
          <<>> -> <<"workflows/three-provinces-six-ministries.v1.json">>;
          <<"undefined">> -> <<"workflows/three-provinces-six-ministries.v1.json">>;
          _ -> Dsl1
        end,
      Opts = openagentic_cli_runtime_opts:runtime_opts(Flags),
      ProjectDir = openagentic_cli_values:ensure_list(maps:get(project_dir, Opts, ".")),
      EngineOpts = Opts#{strict_unknown_fields => true},
      case openagentic_workflow_engine:run(ProjectDir, openagentic_cli_values:to_list(Dsl), Prompt0, EngineOpts) of
        {ok, Res} ->
          WfId = openagentic_cli_values:to_bin(maps:get(workflow_id, Res, <<>>)),
          Sid = openagentic_cli_values:to_bin(maps:get(workflow_session_id, Res, <<>>)),
          io:format("~nworkflow_id=~s~nworkflow_session_id=~s~n", [openagentic_cli_values:to_list(WfId), openagentic_cli_values:to_list(Sid)]),
          ok;
        {error, Reason} ->
          io:format("~nERROR: ~p~n", [Reason]),
          halt(1)
      end
  end.

web_cmd(Args0) ->
  {Flags, _Pos} = openagentic_cli_flags:parse_flags(Args0, #{}),
  Opts0 = openagentic_cli_runtime_opts:runtime_opts(Flags),
  %% Web UI uses its own HITL channel (/api/questions/answer). Avoid console prompts in server mode.
  Opts1 = Opts0#{user_answerer => undefined, permission_gate => openagentic_permissions:default(undefined)},
  Bind0 = maps:get(web_bind, Flags, maps:get(webBind, Flags, undefined)),
  Port0 = maps:get(web_port, Flags, maps:get(webPort, Flags, undefined)),
  Opts =
    Opts1#{
      web_bind => openagentic_cli_values:to_bin(Bind0),
      web_port => Port0
    },
  case start_web_runtime_unlinked(Opts) of
    {ok, #{url := Url}} ->
      io:format("~nWeb UI: ~ts~n", [openagentic_cli_values:to_text(Url)]),
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
