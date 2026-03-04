-module(openagentic_tool_slash_command).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"SlashCommand">>.

description() ->
  <<"Load and render a slash command template (opencode-compatible).">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),

  Name0 = maps:get(<<"name">>, Input, maps:get(name, Input, undefined)),
  case Name0 of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"SlashCommand: 'name' must be a non-empty string">>}};
    _ ->
      Name = string:trim(to_bin(Name0)),
      case byte_size(Name) > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"SlashCommand: 'name' must be a non-empty string">>}};
        true ->
          Args =
            maps:get(
              <<"args">>,
              Input,
              maps:get(args, Input, maps:get(<<"arguments">>, Input, maps:get(arguments, Input, <<>>)))
            ),
          ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
          Base0 = maps:get(<<"project_dir">>, Input, maps:get(project_dir, Input, undefined)),
          Base =
            case Base0 of
              undefined ->
                ProjectDir0;
              _ ->
                case openagentic_fs:resolve_tool_path(ProjectDir0, Base0) of
                  {ok, P} -> P;
                  {error, _} -> ProjectDir0
                end
            end,
          do_run(Name, to_bin(Args), ensure_list(Base))
      end
  end.

do_run(Name, Args, Base) ->
  case load_template(Name, Base) of
    {ok, Tpl} ->
      WorktreeRoot = find_worktree_root(Base),
      Rendered = render_template(maps:get(content, Tpl), Args, WorktreeRoot),
      {ok, #{
        name => Name,
        path => maps:get(path, Tpl),
        content => Rendered
      }};
    {error, not_found} ->
      {error, {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"SlashCommand: not found: ">>, Name])}};
    {error, Reason} ->
      {error, Reason}
  end.

load_template(Name, Base) ->
  Candidates = template_candidates(Name, Base),
  case first_existing(Candidates) of
    {ok, Path} ->
      case file:read_file(Path) of
        {ok, Bin} ->
          {ok, #{path => norm_bin(Path), content => Bin}};
        Err ->
          Err
      end;
    {error, not_found} ->
      {error, not_found}
  end.

template_candidates(Name, Base) ->
  [
    filename:join([Base, ".opencode", "commands", bin_to_list(Name) ++ ".md"]),
    filename:join([Base, ".claude", "commands", bin_to_list(Name) ++ ".md"]),
    filename:join([default_global_opencode_config_dir(), "commands", bin_to_list(Name) ++ ".md"])
  ].

default_global_opencode_config_dir() ->
  case os:getenv("OPENCODE_CONFIG_DIR") of
    false ->
      Home = case os:getenv("USERPROFILE") of false -> "."; V -> V end,
      filename:join([Home, ".config", "opencode"]);
    "" ->
      default_global_opencode_config_dir();
    V ->
      ensure_list(V)
  end.

first_existing([]) ->
  {error, not_found};
first_existing([P | Rest]) ->
  case filelib:is_file(P) of
    true -> {ok, P};
    false -> first_existing(Rest)
  end.

find_worktree_root(Start0) ->
  Start = ensure_list(Start0),
  Cur0 = case string:trim(Start) of "" -> "."; V -> V end,
  Cur = filename:absname(Cur0),
  find_worktree_root_loop(Cur).

find_worktree_root_loop(Cur) ->
  Git = filename:join([Cur, ".git"]),
  case filelib:is_dir(Git) orelse filelib:is_file(Git) of
    true ->
      norm_bin(Cur);
    false ->
      Parent = filename:dirname(Cur),
      case Parent =:= Cur of
        true ->
          norm_bin(Cur);
        false ->
          find_worktree_root_loop(Parent)
      end
  end.

render_template(Content0, Args0, Path0) ->
  Content = to_bin(Content0),
  Args = to_bin(Args0),
  Path = to_bin(Path0),
  Repls = [
    {<<"${args}">>, Args},
    {<<"${path}">>, Path},
    {<<"{{args}}">>, Args},
    {<<"{{path}}">>, Path}
  ],
  lists:foldl(fun ({From, To}, Acc) -> binary:replace(Acc, From, To, [global]) end, Content, Repls).

norm_bin(Path0) ->
  Path = ensure_list(Path0),
  iolist_to_binary(string:replace(Path, "\\", "/", all)).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

bin_to_list(B) when is_binary(B) -> binary_to_list(B);
bin_to_list(L) when is_list(L) -> L;
bin_to_list(A) when is_atom(A) -> atom_to_list(A);
bin_to_list(I) when is_integer(I) -> integer_to_list(I);
bin_to_list(Other) -> ensure_list(Other).
