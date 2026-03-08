-module(openagentic_skills_markdown).

-export([parse_skill_markdown/1]).

parse_skill_markdown(Bin) when is_binary(Bin) ->
  Lines0 = binary:split(Bin, <<"
">>, [global]),
  {Meta, Lines1} = parse_front_matter(Lines0),
  BodyBin = join_lines(Lines1, Bin),
  {TitleName, TitleIdx} = openagentic_skills_sections:first_h1(Lines1),
  Summary = openagentic_skills_sections:paragraph_after_title(Lines1, TitleIdx),
  Checklist = openagentic_skills_sections:checklist_items(Lines1),
  #{meta => Meta, title_name => TitleName, summary => Summary, checklist => Checklist, body => BodyBin}.

parse_front_matter([First | Rest]) ->
  case openagentic_skills_utils:trim(First) of
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

parse_front_matter_kv([], _Meta) -> unterminated;
parse_front_matter_kv([Line | Rest], Meta0) ->
  case openagentic_skills_utils:trim(Line) of
    <<"---">> -> {ok, Meta0, Rest};
    _ ->
      Meta1 = case parse_kv(Line) of {ok, K, V} -> Meta0#{K => V}; _ -> Meta0 end,
      parse_front_matter_kv(Rest, Meta1)
  end.

join_lines(Lines, OrigBin) ->
  Body = iolist_to_binary(lists:join(<<"
">>, Lines)),
  case byte_size(OrigBin) of
    0 -> Body;
    _ -> case binary:last(OrigBin) of $
 -> <<Body/binary, "
">>; _ -> Body end
  end.

parse_kv(Line0) ->
  Line = openagentic_skills_utils:trim(Line0),
  case binary:match(Line, <<":">>) of
    nomatch -> error;
    {Pos, 1} ->
      <<K0:Pos/binary, _Colon:1/binary, V0/binary>> = Line,
      K = to_key(openagentic_skills_utils:trim(K0)),
      V = strip_wrapping_quotes(openagentic_skills_utils:trim(V0)),
      {ok, K, V}
  end.

to_key(<<"name">>) -> name;
to_key(<<"description">>) -> description;
to_key(Other) -> Other.

strip_wrapping_quotes(Bin) ->
  Size = byte_size(Bin),
  case Size >= 2 of
    false -> Bin;
    true ->
      First = binary:at(Bin, 0),
      Last = binary:at(Bin, Size - 1),
      case {First, Last} of
        {$", $"} -> binary:part(Bin, 1, Size - 2);
        {$', $'} -> binary:part(Bin, 1, Size - 2);
        _ -> Bin
      end
  end.
