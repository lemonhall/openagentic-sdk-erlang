-module(openagentic_tool_read_utils).

-export([ensure_map/1, is_sensitive_basename/1, optional_int_field/3, string_field/2, to_bin/1]).

optional_int_field(Map, Keys, FieldName) ->
  Value = first_value(Map, Keys),
  case Value of
    undefined -> {ok, undefined};
    Int when is_integer(Int) -> {ok, Int};
    Bin when is_binary(Bin) -> optional_int_from_binary(string:trim(Bin), FieldName);
    List when is_list(List) -> optional_int_field(#{x => unicode:characters_to_binary(List, utf8)}, [x], FieldName);
    _ -> {error, int_error(FieldName)}
  end.

optional_int_from_binary(<<>>, _FieldName) -> {ok, undefined};
optional_int_from_binary(Bin, FieldName) ->
  case catch binary_to_integer(Bin) of
    Int when is_integer(Int) -> {ok, Int};
    _ -> {error, int_error(FieldName)}
  end.

int_error(FieldName) ->
  iolist_to_binary([<<"Read: '">>, FieldName, <<"' must be an integer">>]).

string_field(Map, Keys) ->
  case first_value(Map, Keys) of
    undefined -> undefined;
    Bin when is_binary(Bin) ->
      case string:trim(Bin) of
        <<>> -> undefined;
        Trimmed -> {ok, Trimmed}
      end;
    List when is_list(List) ->
      string_field(#{x => unicode:characters_to_binary(List, utf8)}, [x]);
    _ ->
      {error, <<"Read: 'file_path' must be a non-empty string">>}
  end.

first_value(Map, Keys) ->
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

is_sensitive_basename(Path0) ->
  Path = to_bin(Path0),
  Base = string:lowercase(to_bin(filename:basename(binary_to_list(Path)))),
  case Base of
    <<".env">> -> true;
    <<"id_rsa">> -> true;
    <<"id_ed25519">> -> true;
    _ ->
      case Base of
        <<".env.", _/binary>> -> Base =/= <<".env.example">>;
        _ ->
          Ext = string:lowercase(filename:extension(binary_to_list(Base))),
          lists:member(Ext, [".pem", ".key", ".p12", ".pfx"])
      end
  end.

to_bin(Bin) when is_binary(Bin) -> Bin;
to_bin(List) when is_list(List) -> iolist_to_binary(List);
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
