-module(openagentic_tool_grep_utils).

-export([bool_opt/3, ensure_list/1, ensure_map/1, first_non_empty/2, int_opt/3, pattern_syntax_message/2, to_bin/1]).

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [Key | Rest]) ->
  case maps:get(Key, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    Value ->
      Bin = to_bin(Value),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
  end.

int_opt(Map, Keys, Default) ->
  case opt_value(Map, Keys) of
    undefined -> Default;
    Int when is_integer(Int) -> Int;
    Bin when is_binary(Bin) -> int_from_binary(Bin, Default);
    List when is_list(List) -> int_from_list(List, Default);
    _ -> Default
  end.

int_from_binary(Bin, Default) ->
  case catch binary_to_integer(string:trim(Bin)) of
    Int when is_integer(Int) -> Int;
    _ -> Default
  end.

int_from_list(List, Default) ->
  case catch list_to_integer(string:trim(List)) of
    Int when is_integer(Int) -> Int;
    _ -> Default
  end.

bool_opt(Map, Keys, Default) ->
  case opt_value(Map, Keys) of
    undefined -> Default;
    true -> true;
    false -> false;
    Bin when is_binary(Bin) -> bool_from_text(string:lowercase(string:trim(Bin)), Default);
    List when is_list(List) -> bool_from_text(string:lowercase(string:trim(List)), Default);
    _ -> Default
  end.

bool_from_text(<<"true">>, _Default) -> true;
bool_from_text(<<"false">>, _Default) -> false;
bool_from_text("true", _Default) -> true;
bool_from_text("false", _Default) -> false;
bool_from_text(_, Default) -> Default.

opt_value(Map, Keys) ->
  lists:foldl(
    fun (Key, Acc) ->
      case Acc of
        undefined -> maps:get(Key, Map, undefined);
        _ -> Acc
      end
    end,
    undefined,
    Keys
  ).

ensure_map(Map) when is_map(Map) -> Map;
ensure_map(List) when is_list(List) -> maps:from_list(List);
ensure_map(_) -> #{}.

ensure_list(Bin) when is_binary(Bin) -> binary_to_list(Bin);
ensure_list(List) when is_list(List) -> List;
ensure_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> iolist_to_binary(List);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Int) when is_integer(Int) -> iolist_to_binary(integer_to_list(Int));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

pattern_syntax_message(Pattern0, Err0) ->
  Pattern = to_bin(Pattern0),
  {Desc0, Pos0} =
    case Err0 of
      {Desc, Pos} when (is_list(Desc) orelse is_binary(Desc)) andalso is_integer(Pos) -> {to_bin(Desc), Pos};
      Desc when is_list(Desc) orelse is_binary(Desc) -> {to_bin(Desc), 1};
      _ -> {to_bin(Err0), 1}
    end,
  Idx0 =
    case Pos0 of
      Int when is_integer(Int), Int > 0 -> Int - 1;
      _ -> 0
    end,
  Spaces = lists:duplicate(Idx0, $\s),
  iolist_to_binary([Desc0, <<" near index ">>, integer_to_binary(Idx0), <<"
">>, Pattern, <<"
">>, Spaces, <<"^">>]).
