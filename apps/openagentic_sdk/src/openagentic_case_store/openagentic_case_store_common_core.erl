-module(openagentic_case_store_common_core).
-export([is_bullet_line/1, strip_bullet/1, trim_bin/1, trim_left/1, trim_right/1, normalize_newlines/1, ensure_list_of_maps/1, ensure_map/1, ensure_list/1, to_bin/1, unique_binaries/1, normalize_candidate_specs/1]).

is_bullet_line(<<"- ", _/binary>>) -> true;
is_bullet_line(<<"* ", _/binary>>) -> true;
is_bullet_line(<<"? ", _/binary>>) -> true;
is_bullet_line(_) -> false.

strip_bullet(<<"- ", Rest/binary>>) -> trim_bin(Rest);
strip_bullet(<<"* ", Rest/binary>>) -> trim_bin(Rest);
strip_bullet(<<226,128,162,32, Rest/binary>>) -> trim_bin(Rest);
strip_bullet(Line) -> trim_bin(Line).

trim_bin(Bin0) ->
  trim_right(trim_left(to_bin(Bin0))).

trim_left(<<C, Rest/binary>>) when C =:= 32; C =:= 9; C =:= 10; C =:= 13 ->
  trim_left(Rest);
trim_left(Bin) ->
  Bin.

trim_right(Bin) ->
  case byte_size(Bin) of
    0 -> <<>>;
    Size ->
      Last = binary:at(Bin, Size - 1),
      case (Last =:= 32) orelse (Last =:= 9) orelse (Last =:= 10) orelse (Last =:= 13) of
        true -> trim_right(binary:part(Bin, 0, Size - 1));
        false -> Bin
      end
  end.

normalize_newlines(Bin) ->
  binary:replace(binary:replace(Bin, <<"\r\n">>, <<"\n">>, [global]), <<"\r">>, <<"\n">>, [global]).

ensure_list_of_maps(List) when is_list(List) -> [ensure_map(Item) || Item <- List];
ensure_list_of_maps(_) -> [].

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) ->
  case lists:all(fun (Item) -> is_tuple(Item) andalso tuple_size(Item) =:= 2 end, L) of
    true -> maps:from_list(L);
    false -> #{}
  end;
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(F) when is_float(F) -> iolist_to_binary(io_lib:format("~p", [F]));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

unique_binaries(List0) ->
  lists:usort([Item || Item <- List0, is_binary(Item), Item =/= <<>>]).

normalize_candidate_specs([]) -> [];
normalize_candidate_specs(Items) when is_list(Items) -> [ensure_map(Item) || Item <- Items];
normalize_candidate_specs(_) -> [].
