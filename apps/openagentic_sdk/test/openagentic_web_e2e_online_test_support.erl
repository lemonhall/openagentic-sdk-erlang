-module(openagentic_web_e2e_online_test_support).
-export([ensure_httpc_started/0, ensure_list/1, http_post_json/2, pick_port/0, should_run/0, tmp_root/0]).

-define(HTTPC_PROFILE, openagentic_web_e2e).

http_post_json(Url0, Obj0) ->
  Url = ensure_list(Url0),
  Body = openagentic_json:encode_safe(Obj0),
  Headers = [{"content-type", "application/json"}],
  HttpOptions = [{timeout, 60000}],
  Opts = [{body_format, binary}],
  case httpc:request(post, {Url, Headers, "application/json", Body}, HttpOptions, Opts, ?HTTPC_PROFILE) of
    {ok, {{_, Status, _}, _RespHeaders, RespBody}} ->
      Resp =
        case string:trim(RespBody) of
          <<>> -> #{};
          B ->
            case (catch openagentic_json:decode(B)) of
              M when is_map(M) -> M;
              _ -> #{}
            end
        end,
      {Status, Resp};
    Other ->
      erlang:error({http_request_failed, Other})
  end.

ensure_httpc_started() ->
  DataDir = filename:join([tmp_root(), "httpc"]),
  ok = filelib:ensure_dir(filename:join([DataDir, "x"])),
  _ = inets:start(httpc, [{profile, ?HTTPC_PROFILE}, {data_dir, DataDir}]),
  ok.

%% ---- config ----

should_run() ->
  case os:getenv("OPENAGENTIC_E2E") of
    false -> {skip, disabled};
    "" -> {skip, disabled};
    _ ->
      {ok, Cwd} = file:get_cwd(),
      ProjectDir = ensure_list(Cwd),
      DotEnv = openagentic_dotenv:load(filename:join([ProjectDir, ".env"])),
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
      case {ApiKey, Model} of
        {undefined, _} -> {skip, missing_api_key};
        {_, undefined} -> {skip, missing_model};
        _ ->
          SessionRoot = tmp_root(),
          Port = pick_port(),
          UserAnswerer = fun (_Q) -> <<"no">> end,
          Gate = openagentic_permissions:default(UserAnswerer),
          Opts =
            #{
              api_key => ApiKey,
              model => Model,
              base_url => BaseUrl,
              api_key_header => ApiKeyHeader,
              protocol => responses,
              include_partial_messages => true,
              permission_gate => Gate,
              user_answerer => UserAnswerer,
              event_sink => fun (_Ev) -> ok end
            },
          {ok, #{project_dir => ProjectDir, session_root => SessionRoot, port => Port, runtime_opts => Opts}}
      end
  end.

tmp_root() ->
  {ok, Cwd} = file:get_cwd(),
  Base = filename:join([ensure_list(Cwd), ".tmp", "e2e", "openagentic_web_e2e_online_test"]),
  Id = lists:flatten(io_lib:format("~p_~p", [erlang:system_time(microsecond), erlang:unique_integer([positive, monotonic])])),
  Root = filename:join([Base, Id]),
  ok = filelib:ensure_dir(filename:join([Root, "x"])),
  Root.

pick_port() ->
  %% Best-effort: ask OS for an ephemeral port, then use it for Cowboy.
  case gen_tcp:listen(0, [{ip, {127, 0, 0, 1}}, binary, {active, false}]) of
    {ok, Sock} ->
      {ok, {_Ip, Port}} = inet:sockname(Sock),
      ok = gen_tcp:close(Sock),
      Port;
    _ ->
      18088
  end.

first_non_blank([H | T]) ->
  case to_bin(H) of
    <<>> -> first_non_blank(T);
    <<"undefined">> -> first_non_blank(T);
    B -> B
  end;
first_non_blank([]) ->
  undefined.

to_bin(false) -> <<>>;
to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).
