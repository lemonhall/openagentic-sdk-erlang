-module(openagentic_e2e_online_utils).
-export([
  ensure_dir/1,
  ensure_list/1,
  ensure_map/1,
  ensure_required_cfg/1,
  first_non_blank/1,
  load_cfg/1,
  rand_hex/1,
  repo_root/0,
  to_bin/1,
  to_bool/2
]).

repo_root() ->
  case file:get_cwd() of
    {ok, Cwd} -> Cwd;
    _ -> "."
  end.

load_cfg(DotEnv) ->
  ApiKey = first_non_blank([openagentic_dotenv:get(<<"OPENAI_API_KEY">>, DotEnv), os:getenv("OPENAI_API_KEY")]),
  Model =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_MODEL">>, DotEnv),
      openagentic_dotenv:get(<<"MODEL">>, DotEnv),
      os:getenv("OPENAI_MODEL"),
      os:getenv("MODEL")
    ]),
  BaseUrl =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_BASE_URL">>, DotEnv),
      os:getenv("OPENAI_BASE_URL"),
      <<"https://api.openai.com/v1">>
    ]),
  ApiKeyHeader =
    first_non_blank([
      openagentic_dotenv:get(<<"OPENAI_API_KEY_HEADER">>, DotEnv),
      os:getenv("OPENAI_API_KEY_HEADER"),
      <<"authorization">>
    ]),
  Store0 = first_non_blank([openagentic_dotenv:get(<<"OPENAI_STORE">>, DotEnv), os:getenv("OPENAI_STORE")]),
  Store = to_bool(Store0, true),
  SessionRoot = ensure_list(openagentic_paths:default_session_root()),
  #{
    api_key => ApiKey,
    model => Model,
    base_url => BaseUrl,
    api_key_header => ApiKeyHeader,
    openai_store => Store,
    session_root => SessionRoot,
    timeout_ms => 60000
  }.

ensure_required_cfg(Cfg) ->
  case {maps:get(api_key, Cfg, undefined), maps:get(model, Cfg, undefined), maps:get(base_url, Cfg, undefined)} of
    {undefined, _, _} -> erlang:error(missing_api_key);
    {_, undefined, _} -> erlang:error(missing_model);
    {_, _, undefined} -> erlang:error(missing_base_url);
    _ -> ok
  end.

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

ensure_dir(Path0) ->
  Path = ensure_list(Path0),
  ok = filelib:ensure_dir(Path),
  ok.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).

to_bool(undefined, Default) -> Default;
to_bool(null, Default) -> Default;
to_bool(false, Default) -> Default;
to_bool(true, _Default) -> true;
to_bool(1, _Default) -> true;
to_bool(0, _Default) -> false;
to_bool(V, Default) ->
  S = string:lowercase(string:trim(to_bin(V))),
  case S of
    <<"1">> -> true;
    <<"true">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    <<"on">> -> true;
    <<"0">> -> false;
    <<"false">> -> false;
    <<"no">> -> false;
    <<"n">> -> false;
    <<"off">> -> false;
    _ -> Default
  end.

rand_hex(Bytes) when is_integer(Bytes), Bytes > 0 ->
  _ = application:ensure_all_started(crypto),
  binary:encode_hex(crypto:strong_rand_bytes(Bytes), lowercase).
