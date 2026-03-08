-module(openagentic_runtime_truncate_hint).
-export([safe_piece/1,safe_char/1,build_truncation_hint/2,truncate_bin/2]).

safe_piece(S0) ->
  S1 = string:trim(openagentic_runtime_utils:ensure_list(S0)),
  S = case S1 of "" -> "x"; _ -> S1 end,
  Out0 = [safe_char(C) || C <- S],
  Out = lists:sublist(Out0, 120),
  case Out of [] -> "x"; _ -> Out end.

safe_char(C) when C >= $a, C =< $z -> C;
safe_char(C) when C >= $A, C =< $Z -> C;
safe_char(C) when C >= $0, C =< $9 -> C;

safe_char($_) -> $_;
safe_char($-) -> $-;
safe_char($.) -> $.;
safe_char(_) -> $_.

build_truncation_hint(ArtifactPath0, State0) ->
  Saved =
    case ArtifactPath0 of
      undefined -> <<"(unavailable)">>;
      "" -> <<"(unavailable)">>;
      <<>> -> <<"(unavailable)">>;
      P -> openagentic_runtime_utils:to_bin(P)
    end,
  TaskRunner = maps:get(task_runner, State0, undefined),
  AllowedTools = maps:get(allowed_tools, State0, undefined),
  TaskAllowed = (TaskRunner =/= undefined) andalso openagentic_runtime_options:is_tool_allowed(AllowedTools, <<"Task">>),
  TaskAgents0 = maps:get(task_agents, State0, []),
  TaskAgents = [openagentic_runtime_utils:to_bin(A) || A <- openagentic_runtime_utils:ensure_list(TaskAgents0)],
  HasExplore = lists:any(fun (A) -> A =:= <<"explore">> end, TaskAgents),
  case TaskAllowed andalso HasExplore of
    true ->
      iolist_to_binary(lists:join(<<"\n">>, [
        <<"The tool call succeeded but the output was truncated.">>,
        iolist_to_binary([<<"Full output saved to: ">>, Saved]),
        <<"Next: Use Task(agent=\"explore\") to grep/read only relevant parts (offset/limit). Do NOT read the full file yourself.">>
      ]));
    false ->
      iolist_to_binary(lists:join(<<"\n">>, [
        <<"The tool call succeeded but the output was truncated.">>,
        iolist_to_binary([<<"Full output saved to: ">>, Saved]),
        <<"Next: Use Grep to search and Read with offset/limit to view specific sections (avoid reading the full file).">>
      ]))
  end.

truncate_bin(Bin0, MaxChars0) ->
  Bin = openagentic_runtime_utils:to_bin(Bin0),
  MaxChars = erlang:max(0, MaxChars0),
  case MaxChars =< 0 of
    true ->
      <<>>;
    false ->
      try
        L = unicode:characters_to_list(Bin, utf8),
        case length(L) =< MaxChars of
          true -> unicode:characters_to_binary(L, utf8);
          false -> unicode:characters_to_binary(lists:sublist(L, MaxChars), utf8)
        end
      catch
        _:_ ->
          %% Best-effort: fall back to bytes.
          case byte_size(Bin) =< MaxChars of
            true -> Bin;
            false -> binary:part(Bin, 0, MaxChars)
          end
      end
  end.
