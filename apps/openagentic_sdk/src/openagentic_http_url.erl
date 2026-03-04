-module(openagentic_http_url).

-export([join/2, trim_end_slashes/1]).

%% Minimal URL join helper (Kotlin parity):
%% - baseUrl.trimEnd('/') + "/" + path.trimStart('/')

join(BaseUrl0, Suffix0) ->
  BaseUrl = trim_end_slashes(to_bin(BaseUrl0)),
  Suffix = trim_start_slashes(to_bin(Suffix0)),
  case {BaseUrl, Suffix} of
    {<<>>, <<>>} -> "";
    {<<>>, S} -> to_list(<<"/", S/binary>>);
    {B, <<>>} -> to_list(B);
    {B, S} -> to_list(<<B/binary, "/", S/binary>>)
  end.

trim_end_slashes(Bin0) ->
  Bin = to_bin(Bin0),
  trim_end_slashes_loop(Bin).

%% internal
trim_end_slashes_loop(<<>>) ->
  <<>>;
trim_end_slashes_loop(Bin) ->
  case binary:last(Bin) of
    $/ ->
      trim_end_slashes_loop(binary:part(Bin, 0, byte_size(Bin) - 1));
    _ ->
      Bin
  end.

trim_start_slashes(Bin0) ->
  Bin = to_bin(Bin0),
  trim_start_slashes_loop(Bin).

trim_start_slashes_loop(<<>>) ->
  <<>>;
trim_start_slashes_loop(<<$/, Rest/binary>>) ->
  trim_start_slashes_loop(Rest);
trim_start_slashes_loop(Bin) ->
  Bin.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

