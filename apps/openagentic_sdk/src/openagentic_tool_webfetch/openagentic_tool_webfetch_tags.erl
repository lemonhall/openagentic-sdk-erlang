-module(openagentic_tool_webfetch_tags).

-export([sanitize_allowlist/2]).

sanitize_allowlist(Html0, BaseUrl0) ->
  BaseUrl = openagentic_tool_webfetch_runtime:to_bin(BaseUrl0),
  Html1 = re:replace(openagentic_tool_webfetch_runtime:to_bin(Html0), <<"<img\\b[^>]*>">>, <<>>, [global, caseless, {return, binary}]),
  Html2 = openagentic_tool_webfetch_anchors:sanitize_anchor_open_tags(Html1, BaseUrl),
  Html3 = strip_attrs_for_allowed(Html2),
  Html4 = filter_disallowed_tags(Html3),
  Html4.

strip_attrs_for_allowed(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Tags = [
    <<"p">>, <<"br">>, <<"ul">>, <<"ol">>, <<"li">>,
    <<"table">>, <<"thead">>, <<"tbody">>, <<"tr">>, <<"td">>, <<"th">>,
    <<"h1">>, <<"h2">>, <<"h3">>, <<"h4">>, <<"h5">>, <<"h6">>,
    <<"pre">>, <<"code">>, <<"blockquote">>, <<"em">>, <<"strong">>
  ],
  lists:foldl(
    fun (T0, Acc0) ->
      T = openagentic_tool_webfetch_runtime:to_list(T0),
      Pat = iolist_to_binary([<<"<(">>, T, <<")\\b[^>]*>">>]),
      re:replace(Acc0, Pat, <<"<\\1>">>, [global, caseless, {return, binary}])
    end,
    Html,
    Tags
  ).

filter_disallowed_tags(Html0) ->
  Html = openagentic_tool_webfetch_runtime:to_bin(Html0),
  Allowed = allowed_tags_set(),
  filter_tags_loop(Html, Allowed, 0, []).

allowed_tags_set() ->
  #{<<"a">> => true, <<"p">> => true, <<"br">> => true,
    <<"ul">> => true, <<"ol">> => true, <<"li">> => true,
    <<"table">> => true, <<"thead">> => true, <<"tbody">> => true, <<"tr">> => true, <<"td">> => true, <<"th">> => true,
    <<"h1">> => true, <<"h2">> => true, <<"h3">> => true, <<"h4">> => true, <<"h5">> => true, <<"h6">> => true,
    <<"pre">> => true, <<"code">> => true, <<"blockquote">> => true, <<"em">> => true, <<"strong">> => true}.

filter_tags_loop(Html, _Allowed, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
filter_tags_loop(Html, Allowed, Pos0, AccRev) ->
  case binary:match(Html, <<"<">>, [{scope, {Pos0, byte_size(Html) - Pos0}}]) of
    nomatch ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]));
    {P, _} ->
      Prefix = binary:part(Html, Pos0, P - Pos0),
      case binary:match(Html, <<">">>, [{scope, {P, byte_size(Html) - P}}]) of
        nomatch ->
          Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
          iolist_to_binary(lists:reverse([Tail | AccRev]));
        {Q, _} ->
          Tag = binary:part(Html, P, Q - P + 1),
          Name = tag_name_lower(Tag),
          Keep = maps:get(Name, Allowed, false),
          Next = Q + 1,
          case Keep of
            true -> filter_tags_loop(Html, Allowed, Next, [Tag, Prefix | AccRev]);
            false -> filter_tags_loop(Html, Allowed, Next, [Prefix | AccRev])
          end
      end
  end.

tag_name_lower(Tag0) ->
  Tag = openagentic_tool_webfetch_runtime:to_bin(Tag0),
  T1 = binary:part(Tag, 1, byte_size(Tag) - 1),
  T2 =
    case T1 of
      <<"/", Rest/binary>> -> Rest;
      _ -> T1
    end,
  %% name ends at first space or '>' or '/'
  Name0 = take_while_name(T2, 0),
  string:lowercase(openagentic_tool_webfetch_runtime:to_bin(Name0)).

take_while_name(Bin, I) ->
  Size = byte_size(Bin),
  take_while_name2(Bin, I, Size).

take_while_name2(_Bin, I, Size) when I >= Size -> <<>>;
take_while_name2(Bin, I, Size) ->
  C = binary:at(Bin, I),
  case (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z) orelse (C >= $0 andalso C =< $9) of
    true ->
      <<C, (take_while_name2(Bin, I + 1, Size))/binary>>;
    false ->
      <<>>
  end.
