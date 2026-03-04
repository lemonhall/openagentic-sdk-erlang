-module(openagentic_tool_skill).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Skill">>.

description() -> <<"Lookup a SKILL.md by name and return its content.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir0 = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),
  ProjectDirIn = maps:get(<<"project_dir">>, Input, maps:get(project_dir, Input, undefined)),
  ProjectDir =
    case ProjectDirIn of
      undefined ->
        ProjectDir0;
      _ ->
        case openagentic_fs:resolve_tool_path(ProjectDir0, ProjectDirIn) of
          {ok, P} -> P;
          {error, _} -> ProjectDir0
        end
    end,
  Name0 =
    maps:get(
      <<"name">>,
      Input,
      maps:get(name, Input, maps:get(<<"skill">>, Input, maps:get(skill, Input, undefined)))
    ),
  case Name0 of
    undefined ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Skill: 'name' must be a non-empty string">>}};
    _ ->
      Name = string:trim(to_bin(Name0)),
      case byte_size(Name) > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Skill: 'name' must be a non-empty string">>}};
        true ->
          case openagentic_skills:get(ProjectDir, Name) of
        {ok, Info} ->
          Path0 = maps:get(path, Info),
          Dir0 = filename:dirname(ensure_list(Path0)),
          Dir = openagentic_fs:norm_abs_bin(Dir0),
          Body = maps:get(body, Info, maps:get(content, Info, <<>>)),
          Output = render_skill_output(maps:get(name, Info), Dir, Body),
          {ok, #{
            title => iolist_to_binary([<<"Loaded skill: ">>, maps:get(name, Info)]),
            name => maps:get(name, Info),
            description => maps:get(description, Info, <<>>),
            summary => maps:get(summary, Info, <<>>),
            checklist => maps:get(checklist, Info, []),
            path => maps:get(path, Info),
            output => Output,
            metadata => #{name => maps:get(name, Info), dir => Dir}
          }};
        {error, not_found} ->
          {error, {kotlin_error, <<"FileNotFoundException">>, skill_not_found_message(ProjectDir, Name)}}
      end
      end
  end.

render_skill_output(Name0, BaseDir0, Body0) ->
  Name = to_bin(Name0),
  BaseDir = to_bin(BaseDir0),
  Body = strip_frontmatter(to_bin(Body0)),
  Body2 = string:trim(Body),
  iolist_to_binary(
    [
      <<"## Skill: ">>, Name, <<"\n\n">>,
      <<"**Base directory**: ">>, BaseDir, <<"\n\n">>,
      Body2
    ]
  ).

strip_frontmatter(Text) when is_binary(Text) ->
  Lines = binary:split(Text, <<"\n">>, [global]),
  case Lines of
    [First | Rest] ->
      case string:trim(First) of
        <<"---">> -> strip_frontmatter_kv(Rest);
        _ -> Text
      end;
    _ ->
      Text
  end.

strip_frontmatter_kv([]) ->
  <<>>;
strip_frontmatter_kv([Line | Rest]) ->
  case string:trim(Line) of
    <<"---">> ->
      iolist_to_binary(lists:join(<<"\n">>, Rest));
    _ ->
      strip_frontmatter_kv(Rest)
  end.

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
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

skill_not_found_message(ProjectDir0, Name0) ->
  ProjectDir = ensure_list(ProjectDir0),
  Name = to_bin(Name0),
  Infos = openagentic_skills:index(ProjectDir),
  Names = [maps:get(name, I) || I <- Infos, is_map(I), maps:is_key(name, I)],
  Available =
    case Names of
      [] -> <<"none">>;
      _ -> iolist_to_binary(lists:join(<<", ">>, Names))
    end,
  iolist_to_binary([<<"Skill: not found: ">>, Name, <<". Available skills: ">>, Available]).
