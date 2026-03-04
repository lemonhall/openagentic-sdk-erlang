-module(openagentic_tool_task).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Task">>.

description() -> <<"Run a subagent by name.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  Agent0 = maps:get(<<"agent">>, Input, maps:get(agent, Input, undefined)),
  Prompt0 = maps:get(<<"prompt">>, Input, maps:get(prompt, Input, undefined)),
  Agent = string:trim(to_bin(Agent0)),
  Prompt = string:trim(to_bin(Prompt0)),
  case {byte_size(Agent) > 0, byte_size(Prompt) > 0} of
    {true, true} ->
      case maps:get(task_runner, Ctx, undefined) of
        F when is_function(F, 3) ->
          SessionId = maps:get(session_id, Ctx, <<>>),
          ToolUseId = maps:get(tool_use_id, Ctx, <<>>),
          ToolCtx = #{session_id => SessionId, tool_use_id => ToolUseId},
          try
            Out = F(Agent, Prompt, ToolCtx),
            {ok, Out}
          catch
            C:R -> {error, {C, R}}
          end;
        _ ->
          {error, {no_task_runner, <<"Task: no taskRunner is configured">>}}
      end;
    _ ->
      {error, {invalid_input, <<"Task: 'agent' and 'prompt' must be non-empty strings">>}}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
