-module(openagentic_skills).

-export([index/1, get/2]).

%% index/1 returns a list of #{name, description, path}.
index(ProjectDir0) ->
  ProjectDir = ensure_list(ProjectDir0),
  AgentsRoot = openagentic_paths:default_agents_root(),
  GlobalRoot = openagentic_paths:default_session_root(),
  ClaudeRoot = filename:join([ProjectDir, ".claude"]),

  %% Precedence: later roots override earlier ones (more local wins).
  Roots = [AgentsRoot, GlobalRoot, ProjectDir, ClaudeRoot],
  Map0 = #{},
  Map =
    lists:foldl(
      fun (Root0, Acc0) ->
        Root = ensure_list(Root0),
        Files = iter_skill_files(Root),
        lists:foldl(
          fun (Path, Acc1) ->
            case read_skill_file(Path) of
              {ok, Info} ->
                Name = maps:get(name, Info, <<>>),
                case Name of
                  <<>> -> Acc1;
                  _ -> Acc1#{Name => Info}
                end;
              _ ->
                Acc1
            end
          end,
          Acc0,
          Files
        )
      end,
      Map0,
      Roots
    ),
  lists:sort(fun (A, B) -> maps:get(name, A) =< maps:get(name, B) end, maps:values(Map)).

get(ProjectDir0, Name0) ->
  Name = to_bin(Name0),
  Infos = index(ProjectDir0),
  Found = [I || I <- Infos, maps:get(name, I) =:= Name],
  case Found of
    [One | _] -> {ok, One};
    [] -> {error, not_found}
  end.

%% internal
iter_skill_files(Root) ->
  %% NOTE: Don't use lists:flatten/1 here: file paths are strings (lists), and
  %% flattening would concatenate them into a single charlist.
  lists:append([iter_skill_files_dir(filename:join([Root, D])) || D <- ["skill", "skills"]]).

iter_skill_files_dir(Dir) ->
  D = ensure_list(Dir),
  case filelib:is_dir(D) of
    false ->
      [];
    true ->
      iter_skill_walk(D, [])
  end.

iter_skill_walk(Dir, Acc0) ->
  Children =
    case file:list_dir(Dir) of
      {ok, Names} -> lists:sort(Names);
      _ -> []
    end,
  lists:foldl(
    fun (Name0, Acc1) ->
      Name = ensure_list(Name0),
      Full = filename:join([Dir, Name]),
      case filelib:is_dir(Full) of
        true ->
          iter_skill_walk(Full, Acc1);
        false ->
          case filename:basename(Full) of
            "SKILL.md" -> [Full | Acc1];
            _ -> Acc1
          end
      end
    end,
    Acc0,
    Children
  ).

read_skill_file(Path0) ->
  Path = ensure_list(Path0),
  case file:read_file(Path) of
    {ok, Bin} ->
      Doc = parse_skill_markdown(Bin),
      Meta = maps:get(meta, Doc, #{}),
      TitleName = maps:get(title_name, Doc, <<>>),
      Name0 =
        case maps:get(name, Meta, <<>>) of
          <<>> ->
            case TitleName of
              <<>> ->
                %% Fallback to parent directory name
                Parent = filename:basename(filename:dirname(Path)),
                to_bin(Parent);
              V2 ->
                V2
            end;
          V ->
            V
        end,
      Desc = maps:get(description, Meta, <<>>),
      Summary = maps:get(summary, Doc, <<>>),
      Checklist = maps:get(checklist, Doc, []),
      Body = maps:get(body, Doc, Bin),
      {ok, #{
        name => Name0,
        description => Desc,
        summary => Summary,
        checklist => Checklist,
        path => to_bin(Path),
        content => Bin,
        body => Body
      }};
    Err ->
      Err
  end.

parse_skill_markdown(Bin) when is_binary(Bin) ->
  %% Kotlin-aligned:
  %% - optional YAML-ish front matter delimited by --- lines
  %% - name from "# " heading (front matter 'name' overrides later)
  %% - summary = first paragraph after title
  %% - checklist = bullets under "## Checklist"
  Lines0 = binary:split(Bin, <<"\n">>, [global]),
  {Meta, Lines1} = parse_front_matter(Lines0),
  BodyBin = join_lines(Lines1, Bin),
  {TitleName, TitleIdx} = first_h1(Lines1),
  Summary = paragraph_after_title(Lines1, TitleIdx),
  Checklist = checklist_items(Lines1),
  #{
    meta => Meta,
    title_name => TitleName,
    summary => Summary,
    checklist => Checklist,
    body => BodyBin
  }.

parse_front_matter([First | Rest]) ->
  case trim(First) of
    <<"---">> ->
      case parse_front_matter_kv(Rest, #{}) of
        {ok, Meta, After} -> {Meta, After};
        unterminated -> {#{}, [First | Rest]}
      end;
    _ ->
      {#{}, [First | Rest]}
  end;
parse_front_matter([]) ->
  {#{}, []}.

parse_front_matter_kv([], _Meta) ->
  unterminated;
parse_front_matter_kv([Line | Rest], Meta0) ->
  case trim(Line) of
    <<"---">> ->
      {ok, Meta0, Rest};
    _ ->
      Meta1 =
        case parse_kv(Line) of
          {ok, K, V} -> Meta0#{K => V};
          _ -> Meta0
        end,
      parse_front_matter_kv(Rest, Meta1)
  end.

join_lines(Lines, OrigBin) ->
  %% Reconstruct body preserving trailing newline behavior (like Kotlin).
  Body = iolist_to_binary(lists:join(<<"\n">>, Lines)),
  case byte_size(OrigBin) of
    0 ->
      Body;
    _ ->
      case binary:last(OrigBin) of
        $\n -> <<Body/binary, "\n">>;
        _ -> Body
      end
  end.

first_h1(Lines) ->
  first_h1(Lines, 0).

first_h1([], _Idx) ->
  {<<>>, undefined};
first_h1([L | Rest], Idx) ->
  case is_h1(L) of
    true ->
      Sz = byte_size(L),
      Name = trim(binary:part(L, 2, Sz - 2)),
      {Name, Idx};
    false ->
      first_h1(Rest, Idx + 1)
  end.

paragraph_after_title(Lines, undefined) ->
  paragraph_from(Lines, 0);
paragraph_after_title(Lines, TitleIdx) ->
  paragraph_from(Lines, TitleIdx + 1).

paragraph_from(Lines, Start0) ->
  Start = skip_blanks(Lines, Start0),
  paragraph_collect(Lines, Start, []).

skip_blanks(Lines, I) ->
  case nthtail_safe(I, Lines) of
    [] -> I;
    [L | _] ->
      case trim(L) of
        <<>> -> skip_blanks(Lines, I + 1);
        _ -> I
      end
  end.

paragraph_collect(Lines, I, Acc0) ->
  case nthtail_safe(I, Lines) of
    [] ->
      join_trimmed_rev(Acc0);
    [L | _] ->
      T = trim(L),
      case T of
        <<>> ->
          join_trimmed_rev(Acc0);
        _ ->
          case is_heading(T) of
            true ->
              join_trimmed_rev(Acc0);
            false ->
              paragraph_collect(Lines, I + 1, [T | Acc0])
          end
      end
  end.

join_trimmed_rev(AccRev) ->
  iolist_to_binary(lists:join(<<"\n">>, lists:reverse(AccRev))).

checklist_items(Lines) ->
  case find_checklist_start(Lines, 0) of
    undefined -> [];
    Start -> checklist_collect(Lines, Start, [])
  end.

find_checklist_start([], _I) ->
  undefined;
find_checklist_start([L | Rest], I) ->
  Lower = string:lowercase(trim(L)),
  case Lower of
    <<"## checklist">> -> I + 1;
    _ -> find_checklist_start(Rest, I + 1)
  end.

checklist_collect(Lines, I, Acc0) ->
  case nthtail_safe(I, Lines) of
    [] ->
      lists:reverse(Acc0);
    [L | _] ->
      T = trim(L),
      case T of
        <<>> ->
          checklist_collect(Lines, I + 1, Acc0);
        _ ->
          case is_heading(T) of
            true ->
              lists:reverse(Acc0);
            false ->
              case checklist_bullet_item(T) of
                {ok, Item} -> checklist_collect(Lines, I + 1, [Item | Acc0]);
                error -> checklist_collect(Lines, I + 1, Acc0)
              end
          end
      end
  end.

checklist_bullet_item(<<"-", Rest/binary>>) ->
  Item = trim(Rest),
  case byte_size(Item) > 0 of true -> {ok, Item}; false -> error end;
checklist_bullet_item(<<"*", Rest/binary>>) ->
  Item = trim(Rest),
  case byte_size(Item) > 0 of true -> {ok, Item}; false -> error end;
checklist_bullet_item(_) ->
  error.

parse_kv(Line0) ->
  Line = trim(Line0),
  case binary:match(Line, <<":">>) of
    nomatch ->
      error;
    {Pos, 1} ->
      <<K0:Pos/binary, _Colon:1/binary, V0/binary>> = Line,
      K = to_key(trim(K0)),
      V = strip_wrapping_quotes(trim(V0)),
      {ok, K, V}
  end.

to_key(<<"name">>) -> name;
to_key(<<"description">>) -> description;
to_key(Other) -> Other.

strip_wrapping_quotes(B) ->
  Sz = byte_size(B),
  case Sz >= 2 of
    false -> B;
    true ->
      First = binary:at(B, 0),
      Last = binary:at(B, Sz - 1),
      case {First, Last} of
        {$", $"} -> binary:part(B, 1, Sz - 2);
        {$', $'} -> binary:part(B, 1, Sz - 2);
        _ -> B
      end
  end.

is_h1(<<"# ", _/binary>>) -> true;
is_h1(_) -> false.

is_heading(<<"#", _/binary>>) -> true;
is_heading(_) -> false.

trim(Bin) ->
  trim_left(trim_right(Bin)).

trim_left(<<" ", Rest/binary>>) -> trim_left(Rest);
trim_left(<<"\t", Rest/binary>>) -> trim_left(Rest);
trim_left(B) -> B.

trim_right(Bin) ->
  Sz = byte_size(Bin),
  case Sz of
    0 -> <<>>;
    _ ->
      case binary:at(Bin, Sz - 1) of
        $\s -> trim_right(binary:part(Bin, 0, Sz - 1));
        $\t -> trim_right(binary:part(Bin, 0, Sz - 1));
        $\r -> trim_right(binary:part(Bin, 0, Sz - 1));
        _ -> Bin
      end
  end.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

%% small helper: like lists:nthtail/2 but returns [] when out of range
nthtail_safe(N, List) when N =< 0 -> List;
nthtail_safe(_N, []) -> [];
nthtail_safe(N, [_ | T]) -> nthtail_safe(N - 1, T).
