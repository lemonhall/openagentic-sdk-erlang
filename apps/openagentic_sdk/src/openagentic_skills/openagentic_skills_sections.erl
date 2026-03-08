-module(openagentic_skills_sections).

-export([checklist_items/1, first_h1/1, paragraph_after_title/2]).

first_h1(Lines) -> first_h1(Lines, 0).
first_h1([], _Idx) -> {<<>>, undefined};
first_h1([Line | Rest], Idx) ->
  case is_h1(Line) of
    true ->
      Size = byte_size(Line),
      Name = openagentic_skills_utils:trim(binary:part(Line, 2, Size - 2)),
      {Name, Idx};
    false -> first_h1(Rest, Idx + 1)
  end.

paragraph_after_title(Lines, undefined) -> paragraph_from(Lines, 0);
paragraph_after_title(Lines, TitleIdx) -> paragraph_from(Lines, TitleIdx + 1).

paragraph_from(Lines, Start0) ->
  Start = skip_blanks(Lines, Start0),
  paragraph_collect(Lines, Start, []).

skip_blanks(Lines, Index) ->
  case openagentic_skills_utils:nthtail_safe(Index, Lines) of
    [] -> Index;
    [Line | _] -> case openagentic_skills_utils:trim(Line) of <<>> -> skip_blanks(Lines, Index + 1); _ -> Index end
  end.

paragraph_collect(Lines, Index, Acc0) ->
  case openagentic_skills_utils:nthtail_safe(Index, Lines) of
    [] -> join_trimmed_rev(Acc0);
    [Line | _] ->
      Trimmed = openagentic_skills_utils:trim(Line),
      case Trimmed of
        <<>> -> join_trimmed_rev(Acc0);
        _ -> case is_heading(Trimmed) of true -> join_trimmed_rev(Acc0); false -> paragraph_collect(Lines, Index + 1, [Trimmed | Acc0]) end
      end
  end.

join_trimmed_rev(AccRev) -> iolist_to_binary(lists:join(<<"
">>, lists:reverse(AccRev))).

checklist_items(Lines) ->
  case find_checklist_start(Lines, 0) of undefined -> []; Start -> checklist_collect(Lines, Start, []) end.

find_checklist_start([], _I) -> undefined;
find_checklist_start([Line | Rest], I) ->
  Lower = string:lowercase(openagentic_skills_utils:trim(Line)),
  case Lower of <<"## checklist">> -> I + 1; _ -> find_checklist_start(Rest, I + 1) end.

checklist_collect(Lines, Index, Acc0) ->
  case openagentic_skills_utils:nthtail_safe(Index, Lines) of
    [] -> lists:reverse(Acc0);
    [Line | _] ->
      Trimmed = openagentic_skills_utils:trim(Line),
      case Trimmed of
        <<>> -> checklist_collect(Lines, Index + 1, Acc0);
        _ ->
          case is_heading(Trimmed) of
            true -> lists:reverse(Acc0);
            false ->
              case checklist_bullet_item(Trimmed) of
                {ok, Item} -> checklist_collect(Lines, Index + 1, [Item | Acc0]);
                error -> checklist_collect(Lines, Index + 1, Acc0)
              end
          end
      end
  end.

checklist_bullet_item(<<"-", Rest/binary>>) ->
  Item = openagentic_skills_utils:trim(Rest),
  case byte_size(Item) > 0 of true -> {ok, Item}; false -> error end;
checklist_bullet_item(<<"*", Rest/binary>>) ->
  Item = openagentic_skills_utils:trim(Rest),
  case byte_size(Item) > 0 of true -> {ok, Item}; false -> error end;
checklist_bullet_item(_) -> error.

is_h1(<<"# ", _/binary>>) -> true;
is_h1(_) -> false.

is_heading(<<"#", _/binary>>) -> true;
is_heading(_) -> false.
