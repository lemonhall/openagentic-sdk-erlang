-module(openagentic_cli_project).
-export([resolve_project_dir/1,resolve_project_dir_loop/2,ask_user_answerer/1]).

resolve_project_dir(Dir0) ->
  Dir = openagentic_cli_values:to_list(string:trim(openagentic_cli_values:to_bin(Dir0))),
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
  Q = openagentic_cli_values:ensure_map(Question0),
  Prompt = openagentic_cli_values:to_bin(maps:get(prompt, Q, maps:get(<<"prompt">>, Q, <<>>))),
  Choices0 = openagentic_cli_values:ensure_list(maps:get(choices, Q, maps:get(<<"choices">>, Q, []))),
  Choices = [openagentic_cli_values:to_bin(C) || C <- Choices0],
  io:format("~n~ts~n", [openagentic_cli_values:to_text(Prompt)]),
  case Choices of
    [] ->
      io:get_line("answer> ");
    _ ->
      lists:foreach(fun (C) -> io:format("  - ~ts~n", [openagentic_cli_values:to_text(C)]) end, Choices),
      Ans0 = io:get_line("answer> "),
      string:trim(openagentic_cli_values:to_bin(Ans0))
  end.
