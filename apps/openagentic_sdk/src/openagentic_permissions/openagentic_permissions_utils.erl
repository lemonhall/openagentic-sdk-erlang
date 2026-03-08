-module(openagentic_permissions_utils).

-export([
  ensure_map/1,
  to_bin/1,
  starts_with/2,
  first_non_blank/1,
  mode_upper/1,
  question_id/1,
  parse_allowed/1,
  truncate_bin/2
]).

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

starts_with(Bin0, Prefix0) ->
  Bin = to_bin(Bin0),
  Prefix = to_bin(Prefix0),
  Bs = byte_size(Bin),
  Ps = byte_size(Prefix),
  Bs >= Ps andalso binary:part(Bin, 0, Ps) =:= Prefix.

first_non_blank([]) -> undefined;
first_non_blank([false | Rest]) -> first_non_blank(Rest);
first_non_blank([undefined | Rest]) -> first_non_blank(Rest);
first_non_blank([null | Rest]) -> first_non_blank(Rest);
first_non_blank([V0 | Rest]) ->
  V = string:trim(to_bin(V0)),
  case V of
    <<>> -> first_non_blank(Rest);
    <<"undefined">> -> first_non_blank(Rest);
    _ -> V
  end.

mode_upper(bypass) -> <<"BYPASS">>;
mode_upper(deny) -> <<"DENY">>;
mode_upper(prompt) -> <<"PROMPT">>;
mode_upper(default) -> <<"DEFAULT">>;
mode_upper(A) when is_atom(A) -> mode_upper(prompt);
mode_upper(_) -> <<"PROMPT">>.

question_id(Context) ->
  case maps:get(tool_use_id, Context, maps:get(<<"tool_use_id">>, Context, undefined)) of
    undefined -> random_hex(8);
    V ->
      Bin = to_bin(V),
      case byte_size(Bin) of
        0 -> random_hex(8);
        _ -> Bin
      end
  end.

parse_allowed(Answer0) ->
  case Answer0 of
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    _ ->
      S = string:lowercase(string:trim(to_bin(Answer0))),
      lists:member(S, [<<"y">>, <<"yes">>, <<"true">>, <<"1">>, <<"allow">>, <<"ok">>])
  end.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

truncate_bin(Bin0, Max) when is_integer(Max), Max > 0 ->
  Bin = to_bin(Bin0),
  case byte_size(Bin) > Max of
    true -> <<(binary:part(Bin, 0, Max))/binary, "...">>;
    false -> Bin
  end.
