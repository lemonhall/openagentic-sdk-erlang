-module(openagentic_workflow_engine_utils).
-export([read_workflow_source/2,sha256_hex/1,new_id/0,step_ref/2,put_in/3,uniq_bins/1,join_bins/2,get_any/3,get_any_loop/3,int_or_default/2,clamp_int/3,ensure_map/1,ensure_list_str/1,ensure_list_value/1,to_bin/1,to_bool_default/2]).

read_workflow_source(ProjectDir0, RelPath0) ->
  ProjectDir = ensure_list_str(ProjectDir0),
  RelPath = ensure_list_str(RelPath0),
  case openagentic_fs:resolve_project_path(ProjectDir, RelPath) of
    {ok, Abs} -> file:read_file(Abs);
    {error, unsafe_path} -> {error, unsafe_path}
  end.

sha256_hex(Bin) when is_binary(Bin) ->
  Hash = crypto:hash(sha256, Bin),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Hash]).

new_id() ->
  Bytes = crypto:strong_rand_bytes(16),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

%% ---- generic helpers ----

step_ref(StepRaw, Keys) ->
  V = get_any(StepRaw, Keys, undefined),
  case V of
    null -> null;
    undefined -> null;
    B when is_binary(B) -> string:trim(B);
    L when is_list(L) -> string:trim(iolist_to_binary(L));
    A when is_atom(A) ->
      case A of
        null -> null;
        _ -> atom_to_binary(A, utf8)
      end;
    _ -> null
  end.

put_in(Map0, [K1, K2], V) ->
  M1 = ensure_map(maps:get(K1, Map0, #{})),
  Map0#{K1 := M1#{K2 => V}}.

uniq_bins(L0) ->
  uniq_bins([to_bin(X) || X <- ensure_list_value(L0)], #{}).

uniq_bins([], _Seen) -> [];
uniq_bins([B | Rest], Seen0) ->
  case maps:get(B, Seen0, false) of
    true -> uniq_bins(Rest, Seen0);
    false -> [B | uniq_bins(Rest, Seen0#{B => true})]
  end.

join_bins([], _Sep) -> <<>>;
join_bins([B], _Sep) -> to_bin(B);
join_bins([B | Rest], Sep) -> iolist_to_binary([to_bin(B), Sep, join_bins(Rest, Sep)]).

get_any(Map, Keys, Default) ->
  get_any_loop(ensure_map(Map), Keys, Default).

get_any_loop(_Map, [], Default) -> Default;
get_any_loop(Map, [K | Rest], Default) ->
  case maps:find(K, Map) of
    {ok, V} -> V;
    error -> get_any_loop(Map, Rest, Default)
  end.

int_or_default(V, Default) ->
  case V of
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        I when is_integer(I) -> I;
        _ -> Default
      end;
    _ -> Default
  end.

clamp_int(I, Min, Max) when is_integer(I) ->
  erlang:min(Max, erlang:max(Min, I));
clamp_int(_Other, Min, _Max) ->
  Min.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list_str(B) when is_binary(B) -> binary_to_list(B);
ensure_list_str(L) when is_list(L) -> L;
ensure_list_str(A) when is_atom(A) -> atom_to_list(A);
ensure_list_str(undefined) -> [];
ensure_list_str(null) -> [];
ensure_list_str(Other) -> lists:flatten(io_lib:format("~p", [Other])).

ensure_list_value(L) when is_list(L) -> L;
ensure_list_value(_) -> [].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

to_bool_default(V0, Default) ->
  case V0 of
    true -> true;
    false -> false;
    <<"true">> -> true;
    <<"false">> -> false;
    <<"1">> -> true;
    <<"0">> -> false;
    1 -> true;
    0 -> false;
    _ -> Default
  end.
