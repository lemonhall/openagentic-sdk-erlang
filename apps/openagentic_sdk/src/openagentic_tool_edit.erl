-module(openagentic_tool_edit).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Edit">>.

description() -> <<"Apply a precise edit (string replace) to a file.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),

  FilePath0 = first_value(Input, [<<"file_path">>, file_path, <<"filePath">>, filePath]),
  Old0 = first_value(Input, [<<"old">>, old, <<"old_string">>, old_string, <<"oldString">>, oldString]),
  New0 = first_value(Input, [<<"new">>, new, <<"new_string">>, new_string, <<"newString">>, newString]),

  ReplaceAll = bool_true(first_value(Input, [<<"replace_all">>, replace_all, <<"replaceAll">>, replaceAll])),
  Count0 = int_opt(Input, [<<"count">>, count], undefined),
  Count = case Count0 of undefined -> if ReplaceAll -> 0; true -> 1 end; I -> I end,
  Before = string_opt(first_value(Input, [<<"before">>, before])),
  After = string_opt(first_value(Input, [<<"after">>, 'after'])),

  FilePathOk = is_binary(FilePath0) orelse is_list(FilePath0),
  OldOk = is_binary(Old0) orelse is_list(Old0),
  NewPresent = New0 =/= undefined,
  NewOk = is_binary(New0) orelse is_list(New0),
  case {FilePathOk, OldOk, NewPresent andalso NewOk} of
    {false, _, _} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'file_path' must be a non-empty string">>}};
    {_, false, _} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' must be a non-empty string">>}};
    {_, _, false} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'new' must be a string">>}};
    _ ->
      FilePath = string:trim(to_bin(FilePath0)),
      Old = to_bin(Old0),
      New = to_bin(New0),
      case byte_size(FilePath) > 0 of
        false ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'file_path' must be a non-empty string">>}};
        true ->
          case byte_size(Old) > 0 of
            false ->
              {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' must be a non-empty string">>}};
            true ->
              case is_integer(Count) andalso Count >= 0 of
                false ->
                  {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'count' must be a non-negative integer">>}};
                true ->
                  case openagentic_fs:resolve_tool_path(ProjectDir, FilePath) of
                    {error, Reason} ->
                      {error, Reason};
                    {ok, FullPath0} ->
                      FullPath = ensure_list(FullPath0),
                      edit_file(FullPath, Old, New, Count, Before, After)
                  end
              end
          end
      end
  end.

edit_file(FullPath, Old, New, Count, Before, After) ->
  case file:read_file(FullPath) of
    {ok, Text} ->
      case binary:match(Text, Old) of
        nomatch ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'old' text not found in file">>}};
        {IdxOld, _} ->
          case anchors_ok(Text, IdxOld, Before, After) of
            ok ->
              Occ = occurrences(Text, Old),
              Replaced =
                case Count of
                  0 -> binary:replace(Text, Old, New, [global]);
                  _ -> replace_n(Text, Old, New, Count)
                end,
              ok = file:write_file(FullPath, Replaced),
              Replacements = if Count =:= 0 -> Occ; true -> erlang:min(Occ, Count) end,
              {ok, #{
                message => <<"Edit applied">>,
                file_path => openagentic_fs:norm_abs_bin(FullPath),
                replacements => Replacements
              }};
            {error, Reason} ->
              {error, Reason}
          end
      end;
    Err ->
      {error, edit_io_error(FullPath, Err)}
  end.

edit_io_error(FullPath0, Err0) ->
  FullPath = FullPath0,
  Abs = openagentic_fs:norm_abs_bin(FullPath),
  Reason =
    case Err0 of
      {error, R} -> R;
      R -> R
    end,
  case Reason of
    enoent ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Edit: not found: ">>, Abs])};
    enotdir ->
      {kotlin_error, <<"FileNotFoundException">>, iolist_to_binary([<<"Edit: not found: ">>, Abs])};
    eacces ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Edit: access denied: ">>, Abs])};
    _ ->
      {kotlin_error, <<"RuntimeException">>, iolist_to_binary([<<"Edit failed: ">>, to_bin(Err0)])}
  end.

anchors_ok(_Text, _IdxOld, undefined, undefined) -> ok;
anchors_ok(Text, IdxOld, Before0, After0) ->
  Before = case Before0 of undefined -> undefined; BeforeVal -> to_bin(BeforeVal) end,
  After = case After0 of undefined -> undefined; AfterVal -> to_bin(AfterVal) end,
  IdxBefore = case Before of undefined -> -1; _ -> match_idx(Text, Before) end,
  IdxAfter = case After of undefined -> -1; _ -> match_idx(Text, After) end,
  case Before of
    undefined ->
      after_ok(IdxOld, After, IdxAfter);
    _ when IdxBefore < 0 ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'before' anchor not found in file">>}};
    _ when IdxBefore >= IdxOld ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'before' must appear before 'old'">>}};
    _ ->
      after_ok(IdxOld, After, IdxAfter)
  end.

after_ok(_IdxOld, undefined, _IdxAfter) -> ok;
after_ok(_IdxOld, _After, IdxAfter) when IdxAfter < 0 -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'after' anchor not found in file">>}};
after_ok(IdxOld, _After, IdxAfter) when IdxOld >= IdxAfter -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'after' must appear after 'old'">>}};
after_ok(_IdxOld, _After, _IdxAfter) -> ok.

match_idx(Text, Needle) ->
  case binary:match(Text, Needle) of
    nomatch -> -1;
    {I, _} -> I
  end.

occurrences(Text, Old) ->
  case Old of
    <<>> -> 0;
    _ ->
      Parts = binary:split(Text, Old, [global]),
      case length(Parts) of
        0 -> 0;
        N -> N - 1
      end
  end.

replace_n(Text, _Old, _New, Count) when Count =< 0 ->
  Text;
replace_n(Text, Old, New, Count) ->
  case binary:match(Text, Old) of
    nomatch ->
      Text;
    {Idx, Len} ->
      Prefix = binary:part(Text, 0, Idx),
      Suffix = binary:part(Text, Idx + Len, byte_size(Text) - (Idx + Len)),
      replace_n(iolist_to_binary([Prefix, New, Suffix]), Old, New, Count - 1)
  end.

string_opt(undefined) -> undefined;
string_opt(V0) ->
  case is_stringy(V0) of
    false -> undefined;
    true ->
      V = to_bin(V0),
      case byte_size(string:trim(V)) > 0 of true -> V; false -> undefined end
  end.

first_value(_Map, []) ->
  undefined;
first_value(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_value(Map, Rest);
    V -> V
  end.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of
    <<"true">> -> true;
    <<"1">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    _ -> false
  end;
bool_true(L) when is_list(L) ->
  bool_true(unicode:characters_to_binary(L, utf8));
bool_true(_) ->
  false.

is_stringy(undefined) -> false;
is_stringy(B) when is_binary(B) -> true;
is_stringy(L) when is_list(L) -> true;
is_stringy(_) -> false.
