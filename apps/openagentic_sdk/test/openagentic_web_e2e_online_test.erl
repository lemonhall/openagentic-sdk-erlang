-module(openagentic_web_e2e_online_test).

-include_lib("eunit/include/eunit.hrl").

-define(HTTPC_PROFILE, openagentic_web_e2e).

web_e2e_online_test_() ->
  case should_run() of
    {skip, _Why} ->
      [];
    {ok, Cfg} ->
      {timeout, 300, fun () -> run_e2e(Cfg) end}
  end.

%% ---- e2e ----

run_e2e(Cfg) ->
  ProjectDir = maps:get(project_dir, Cfg),
  Root = maps:get(session_root, Cfg),
  Port = maps:get(port, Cfg),
  Opts = maps:get(runtime_opts, Cfg),

  ok = ensure_httpc_started(),
  {ok, #{url := Url0}} = openagentic_web:start(Opts#{project_dir => ProjectDir, session_root => Root, web_bind => "127.0.0.1", web_port => Port}),
  Url = ensure_list(Url0),

  try
    StartUrl = Url ++ "api/workflows/start",
    Body = #{prompt => <<"hello e2e">>, dsl => <<"workflows/e2e-web-online.v1.json">>},
    {201, StartResp} = http_post_json(StartUrl, Body),
    SidBin = maps:get(<<"workflow_session_id">>, StartResp),
    Sid = ensure_list(SidBin),

    %% Subscribe to SSE and wait for workflow.done.
    EventsUrl = Url ++ "api/sessions/" ++ Sid ++ "/events",
    {ok, _ReqId} = sse_wait_done(EventsUrl, 240000)
  after
    _ = openagentic_web:stop(),
    ok
  end,
  ok.

%% ---- SSE client ----

sse_wait_done(Url0, TimeoutMs) ->
  Url = ensure_list(Url0),
  Headers = [{"accept", "text/event-stream"}],
  HttpOptions = [{timeout, TimeoutMs}],
  Opts = [{sync, false}, {stream, self}, {body_format, binary}],
  {ok, ReqId} = httpc:request(get, {Url, Headers}, HttpOptions, Opts, ?HTTPC_PROFILE),
  receive_done(ReqId, <<>>, undefined, undefined, TimeoutMs).

receive_done(ReqId, Buf0, CurEvent0, CurId0, TimeoutMs) ->
  receive
    {http, {ReqId, stream_start, _Headers}} ->
      receive_done(ReqId, Buf0, CurEvent0, CurId0, TimeoutMs);
    {http, {ReqId, stream, Bin}} ->
      Buf1 = <<Buf0/binary, Bin/binary>>,
      {Buf2, CurEvent, CurId, Done} = sse_parse(Buf1, CurEvent0, CurId0),
      case Done of
        {done, Obj} ->
          %% Ensure we got workflow.done and it's not a raw crash tuple.
          Type = maps:get(<<"type">>, Obj, <<>>),
          ?assertEqual(<<"workflow.done">>, Type),
          Status = maps:get(<<"status">>, Obj, maps:get(status, Obj, <<>>)),
          case Status of
            <<"failed">> ->
              Final = maps:get(<<"final_text">>, Obj, maps:get(final_text, Obj, <<>>)),
              Stack = maps:get(<<"stacktrace">>, Obj, maps:get(stacktrace, Obj, undefined)),
              erlang:error({workflow_failed, Final, Stack});
            _ ->
              ok
          end,
          {ok, ReqId};
        _ ->
          receive_done(ReqId, Buf2, CurEvent, CurId, TimeoutMs)
      end;
    {http, {ReqId, stream_end, _Trailers}} ->
      ?assert(false);
    {http, {ReqId, {error, Reason}}} ->
      erlang:error({http_error, Reason})
  after TimeoutMs ->
    erlang:error(timeout)
  end.

sse_parse(Buf0, CurEvent0, CurId0) ->
  %% Parse one or more SSE frames separated by "\n\n".
  case binary:match(Buf0, <<"\n\n">>) of
    nomatch ->
      {Buf0, CurEvent0, CurId0, none};
    {Pos, _Len} ->
      Frame = binary:part(Buf0, 0, Pos),
      Rest = binary:part(Buf0, Pos + 2, byte_size(Buf0) - (Pos + 2)),
      {CurEvent1, CurId1, Done0} = sse_parse_frame(Frame, CurEvent0, CurId0),
      case Done0 of
        {done, _} = Done ->
          {Rest, CurEvent1, CurId1, Done};
        _ ->
          sse_parse(Rest, CurEvent1, CurId1)
      end
  end.

sse_parse_frame(Frame0, CurEvent0, CurId0) ->
  Frame = string:trim(Frame0),
  Lines = binary:split(Frame, <<"\n">>, [global]),
  lists:foldl(fun sse_line/2, {CurEvent0, CurId0, none}, Lines).

sse_line(<<>>, Acc) ->
  Acc;
sse_line(<<$:,_/binary>>, Acc) ->
  %% comment/keepalive
  Acc;
sse_line(Line0, {CurEvent0, CurId0, Done0}) ->
  Line = string:trim(Line0),
  case Line of
    <<"event: ", Ev/binary>> ->
      {string:trim(Ev), CurId0, Done0};
    <<"id: ", Id/binary>> ->
      {CurEvent0, string:trim(Id), Done0};
    <<"data: ", Data0/binary>> ->
      Data = string:trim(Data0),
      case CurEvent0 of
        <<"workflow.done">> ->
          case (catch openagentic_json:decode(Data)) of
            Obj when is_map(Obj) ->
              {CurEvent0, CurId0, {done, Obj}};
            _ ->
              {CurEvent0, CurId0, Done0}
          end;
        _ ->
          {CurEvent0, CurId0, Done0}
      end;
    _ ->
      {CurEvent0, CurId0, Done0}
  end.

%% ---- HTTP JSON ----

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
