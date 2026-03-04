-module(openagentic_tool_write).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"Write">>.

description() -> <<"Create or overwrite a file.">>.

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
  ProjectDir = maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, ".")),

  FilePath0 =
    first_non_empty(Input, [
      <<"file_path">>, file_path,
      <<"filePath">>, filePath
    ]),
  Content0 = maps:get(<<"content">>, Input, maps:get(content, Input, undefined)),
  Overwrite = bool_true(maps:get(<<"overwrite">>, Input, maps:get(overwrite, Input, false))),

  case {FilePath0, Content0} of
    {undefined, _} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Write: 'file_path' must be a non-empty string">>}};
    {_, undefined} ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Write: 'content' must be a string">>}};
    _ ->
      case {is_stringy(FilePath0), is_stringy(Content0)} of
        {false, _} ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Write: 'file_path' must be a non-empty string">>}};
        {_, false} ->
          {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Write: 'content' must be a string">>}};
        {true, true} ->
          FilePath = string:trim(to_bin(FilePath0)),
          Content = to_bin(Content0),
          case byte_size(FilePath) > 0 of
            false ->
              {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Write: 'file_path' must be a non-empty string">>}};
            true ->
              case openagentic_fs:resolve_tool_path(ProjectDir, FilePath) of
                {error, Reason} ->
                  {error, Reason};
                {ok, FullPath0} ->
                  FullPath = ensure_list(FullPath0),
                  ok = filelib:ensure_dir(FullPath),
                  case {filelib:is_regular(FullPath), Overwrite} of
                    {true, false} ->
                      Msg = iolist_to_binary([<<"Write: file exists: ">>, openagentic_fs:norm_abs_bin(FullPath)]),
                      {error, {kotlin_error, <<"IllegalStateException">>, Msg}};
                    _ ->
                      write_atomic(FullPath, Content)
                  end
              end
          end
      end
  end.

write_atomic(FullPath, Content) ->
  Dir = filename:dirname(FullPath),
  Base = filename:basename(FullPath),
  Tmp = filename:join([Dir, tmp_name(Base)]),
  try
    ok = file:write_file(Tmp, Content),
    ok = file:rename(Tmp, FullPath),
    Bytes = byte_size(Content),
    {ok, #{
      message => iolist_to_binary([<<"Wrote ">>, integer_to_binary(Bytes), <<" bytes">>]),
      file_path => openagentic_fs:norm_abs_bin(FullPath),
      bytes_written => Bytes
    }}
  catch
    C:R ->
      _ = file:delete(Tmp),
      {error, {write_failed, {C, R}}}
  end.

tmp_name(Base0) ->
  Base = ensure_list(Base0),
  Hex = random_hex(16),
  lists:flatten([".", Base, ".", Hex, ".tmp"]).

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  lists:flatten([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

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

is_stringy(B) when is_binary(B) -> true;
is_stringy(L) when is_list(L) -> true;
is_stringy(_) -> false.

first_non_empty(_Map, []) ->
  undefined;
first_non_empty(Map, [K | Rest]) ->
  case maps:get(K, Map, undefined) of
    undefined -> first_non_empty(Map, Rest);
    V ->
      Bin = to_bin(V),
      case byte_size(string:trim(Bin)) > 0 of
        true -> Bin;
        false -> first_non_empty(Map, Rest)
      end
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
