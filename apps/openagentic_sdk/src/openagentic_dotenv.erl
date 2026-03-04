-module(openagentic_dotenv).

-export([load/1, parse/1, get/2]).

%% Minimal .env loader (Kotlin CLI parity).
%% - Ignores blank lines and comments (# ...)
%% - Supports: KEY=VALUE
%% - Strips wrapping single/double quotes from VALUE
%% - Returns a map keyed by binary env var name (e.g. <<"OPENAI_API_KEY">>)

load(Path0) ->
  Path = ensure_list(Path0),
  case file:read_file(Path) of
    {ok, Bin} -> parse(Bin);
    _ -> #{}
  end.

parse(Bin) when is_binary(Bin) ->
  Lines = binary:split(Bin, <<"\n">>, [global]),
  parse_lines(Lines, #{});
parse(L) when is_list(L) ->
  parse(unicode:characters_to_binary(L, utf8));
parse(_) ->
  #{}.

get(Key0, Map0) ->
  Key = to_bin(Key0),
  Map = ensure_map(Map0),
  maps:get(Key, Map, undefined).

%% internal
parse_lines([], Acc) ->
  Acc;
parse_lines([Line0 | Rest], Acc0) ->
  Line1 = strip_cr(Line0),
  Line = string:trim(Line1),
  Acc =
    case Line of
      <<>> -> Acc0;
      _ ->
        case is_comment(Line) of
          true -> Acc0;
          false ->
            parse_kv(Line, Acc0)
        end
    end,
  parse_lines(Rest, Acc).

strip_cr(Bin) when is_binary(Bin) ->
  case byte_size(Bin) > 0 andalso binary:last(Bin) =:= $\r of
    true -> binary:part(Bin, 0, byte_size(Bin) - 1);
    false -> Bin
  end;
strip_cr(Other) ->
  to_bin(Other).

is_comment(<<$#,_/binary>>) -> true;
is_comment(<<$;,_/binary>>) -> true;
is_comment(_) -> false.

parse_kv(Line0, Acc0) ->
  %% tolerate "export KEY=VALUE"
  Line =
    case Line0 of
      <<"export ", Rest/binary>> -> string:trim(Rest);
      _ -> Line0
    end,
  case binary:match(Line, <<"=">>) of
    nomatch ->
      Acc0;
    {Pos, _Len} ->
      K0 = binary:part(Line, 0, Pos),
      V0 = binary:part(Line, Pos + 1, byte_size(Line) - (Pos + 1)),
      K = string:trim(K0),
      case K of
        <<>> -> Acc0;
        _ ->
          V1 = string:trim(V0),
          %% Kotlin parity:
          %% - If value is quoted, take substring between first quote and the last matching quote,
          %%   allowing: KEY="value" # comment
          %% - If value is unquoted, strip inline hash comment: KEY=value # comment
          V = strip_quotes_or_hash_comment(V1),
          Acc0#{K => V}
      end
  end.

strip_quotes_or_hash_comment(Val0) ->
  Val = string:trim(to_bin(Val0)),
  case Val of
    <<>> ->
      <<>>;
    _ ->
      First = binary:at(Val, 0),
      case (First =:= $") orelse (First =:= $') of
        true ->
          strip_wrapping_quote_with_trailing(Val, First);
        false ->
          strip_inline_hash_comment(Val)
      end
  end.

strip_wrapping_quote_with_trailing(Val, Quote) ->
  %% Find the last matching quote (Kotlin uses lastIndexOf).
  %% If not found, keep raw.
  case last_index_of_byte(Val, Quote) of
    I when is_integer(I), I > 0 ->
      binary:part(Val, 1, I - 1);
    _ ->
      Val
  end.

strip_inline_hash_comment(Val) ->
  case binary:match(Val, <<"#">>) of
    nomatch ->
      Val;
    {Pos, _Len} ->
      string:trim(binary:part(Val, 0, Pos), trailing)
  end.

last_index_of_byte(Bin, Byte) when is_binary(Bin), is_integer(Byte) ->
  %% 0-based index; returns -1 if not found.
  Pat = <<Byte>>,
  case binary:matches(Bin, Pat) of
    [] ->
      -1;
    Ms ->
      {Pos, _Len} = lists:last(Ms),
      Pos
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(L) when is_list(L) -> L;
ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
