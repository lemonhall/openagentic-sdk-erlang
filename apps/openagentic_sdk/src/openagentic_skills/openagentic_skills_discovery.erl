-module(openagentic_skills_discovery).

-export([iter_skill_files/1, read_skill_file/1]).

iter_skill_files(Root) ->
  lists:append([iter_skill_files_dir(filename:join([Root, Dir])) || Dir <- ["skill", "skills"]]).

iter_skill_files_dir(Dir) ->
  D = openagentic_skills_utils:ensure_list(Dir),
  case filelib:is_dir(D) of false -> []; true -> iter_skill_walk(D, []) end.

iter_skill_walk(Dir, Acc0) ->
  Children = case file:list_dir(Dir) of {ok, Names} -> lists:sort(Names); _ -> [] end,
  HasSkillFile = lists:member("SKILL.md", Children),
  Acc1 =
    case HasSkillFile of
      true -> [filename:join([Dir, "SKILL.md"]) | Acc0];
      false -> Acc0
    end,
  lists:foldl(
    fun (Name0, Acc2) ->
      Name = openagentic_skills_utils:ensure_list(Name0),
      Full = filename:join([Dir, Name]),
      case filelib:is_dir(Full) of
        true ->
          case should_descend(Name, HasSkillFile) of
            true -> iter_skill_walk(Full, Acc2);
            false -> Acc2
          end;
        false ->
          Acc2
      end
    end,
    Acc1,
    Children
  ).

should_descend(Name0, HasSkillFile) ->
  Name = string:lowercase(openagentic_skills_utils:ensure_list(Name0)),
  case lists:member(Name, [".git", ".hg", ".svn", "node_modules", "__pycache__", ".venv", "venv", "dist", "build"]) of
    true -> false;
    false ->
      case HasSkillFile of
        true -> not lists:member(Name, ["assets", "references", "scripts", "templates"]);
        false -> true
      end
  end.

read_skill_file(Path0) ->
  Path = openagentic_skills_utils:ensure_list(Path0),
  case file:read_file(Path) of
    {ok, Bin} ->
      Doc = openagentic_skills_markdown:parse_skill_markdown(Bin),
      Meta = maps:get(meta, Doc, #{}),
      TitleName = maps:get(title_name, Doc, <<>>),
      Name0 =
        case maps:get(name, Meta, <<>>) of
          <<>> ->
            case TitleName of
              <<>> -> openagentic_skills_utils:to_bin(filename:basename(filename:dirname(Path)));
              Value2 -> Value2
            end;
          Value -> Value
        end,
      Desc = maps:get(description, Meta, <<>>),
      Summary = maps:get(summary, Doc, <<>>),
      Checklist = maps:get(checklist, Doc, []),
      Body = maps:get(body, Doc, Bin),
      {ok, #{name => Name0, description => Desc, summary => Summary, checklist => Checklist, path => openagentic_skills_utils:to_bin(Path), content => Bin, body => Body}};
    Err ->
      Err
  end.
