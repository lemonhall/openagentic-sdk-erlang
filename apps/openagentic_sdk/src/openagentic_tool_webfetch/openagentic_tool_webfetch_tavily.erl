-module(openagentic_tool_webfetch_tavily).

-export([maybe_tavily_extract/8]).

maybe_tavily_extract(RequestedUrl, FinalUrl, Status, RespHeaders, RawText, Text0, Mode, Ctx0) ->
  Ctx = openagentic_tool_webfetch_runtime:ensure_map(Ctx0),
  case should_use_tavily_extract(Status, RespHeaders, RawText, Text0) of
    false -> #{};
    true ->
      DotEnv = openagentic_tool_webfetch_tavily_support:tool_dotenv(Ctx),
      TavilyKey =
        openagentic_tool_webfetch_tavily_support:first_non_blank([
          maps:get(tavily_api_key, Ctx, maps:get(tavilyApiKey, Ctx, undefined)),
          os:getenv("TAVILY_API_KEY"),
          openagentic_dotenv:get(<<"TAVILY_API_KEY">>, DotEnv)
        ]),
      case byte_size(openagentic_tool_webfetch_runtime:to_bin(TavilyKey)) > 0 of
        false -> #{};
        true ->
          Endpoint0 =
            openagentic_tool_webfetch_tavily_support:first_non_blank([
              maps:get(tavily_extract_url, Ctx, maps:get(tavilyExtractUrl, Ctx, undefined)),
              os:getenv("TAVILY_EXTRACT_URL"),
              openagentic_dotenv:get(<<"TAVILY_EXTRACT_URL">>, DotEnv),
              os:getenv("TAVILY_URL"),
              openagentic_dotenv:get(<<"TAVILY_URL">>, DotEnv)
            ]),
          Endpoint = openagentic_tool_webfetch_tavily_support:tavily_extract_endpoint(Endpoint0),
          case tavily_extract(FinalUrl, Mode, TavilyKey, Endpoint, Ctx) of
            {ok, Out} ->
              Out#{
                fetch_via => <<"tavily_extract">>,
                origin_status => Status,
                requested_url => RequestedUrl,
                final_url => FinalUrl,
                tavily_url => Endpoint
              };
            {error, _} ->
              #{}
          end
      end
  end.

should_use_tavily_extract(Status, RespHeaders0, RawText0, Text0) ->
  RespHeaders = openagentic_tool_webfetch_runtime:ensure_map(RespHeaders0),
  ContentType = string:lowercase(openagentic_tool_webfetch_runtime:to_bin(maps:get(<<"content-type">>, RespHeaders, <<>>))),
  RawText = string:lowercase(openagentic_tool_webfetch_sanitize:to_bin_safe_utf8(RawText0)),
  Text = string:lowercase(openagentic_tool_webfetch_sanitize:to_bin_safe_utf8(Text0)),
  BlockedStatus = lists:member(Status, [401, 403, 429]),
  Htmlish =
    (byte_size(ContentType) =:= 0) orelse
      (binary:match(ContentType, <<"text/html">>) =/= nomatch) orelse
      (binary:match(RawText, <<"<html">>) =/= nomatch),
  Placeholder = lists:any(
    fun (Pat) ->
      (binary:match(RawText, Pat) =/= nomatch) orelse (binary:match(Text, Pat) =/= nomatch)
    end,
    [
      <<"please enable javascript">>,
      <<"please enable js">>,
      <<"just a moment">>,
      <<"cloudflare">>,
      <<"attention required">>,
      <<"checking your browser">>,
      <<"verify you are human">>,
      <<"enable cookies">>
    ]
  ),
  Empty = Htmlish andalso byte_size(string:trim(Text)) =:= 0,
  BlockedStatus orelse (Htmlish andalso (Placeholder orelse Empty)).

tavily_extract(Url0, Mode0, TavilyKey, Endpoint0, Ctx) ->
  Url = openagentic_tool_webfetch_runtime:to_bin(Url0),
  Mode = string:lowercase(string:trim(openagentic_tool_webfetch_runtime:to_bin(Mode0))),
  Endpoint = openagentic_tool_webfetch_runtime:to_bin(Endpoint0),
  Payload = #{
    urls => Url,
    query => <<"Extract the main readable content, especially facts, numbers, dates, timelines, and public signals from this page.">>,
    chunks_per_source => 3,
    extract_depth => <<"basic">>,
    include_images => false,
    include_favicon => false,
    format => <<"markdown">>,
    timeout => <<"None">>,
    include_usage => false
  },
  Body = openagentic_json:encode(Payload),
  Headers = [{"authorization", binary_to_list(<<"Bearer ", (openagentic_tool_webfetch_runtime:to_bin(TavilyKey))/binary>>)}, {"content-type", "application/json"}],
  case openagentic_tool_webfetch_tavily_support:http_request(post, Endpoint, Headers, Body, Ctx) of
    {ok, {Status, _RespHeaders, RespBody}} when Status >= 200, Status < 300 ->
      Obj = openagentic_tool_webfetch_runtime:ensure_map(openagentic_json:decode(openagentic_tool_webfetch_sanitize:to_bin_safe_utf8(RespBody))),
      case first_tavily_result(Obj) of
        {ok, #{url := ResultUrl, title := Title, markdown := Md}} ->
          Text = openagentic_tool_webfetch_tavily_format:tavily_text_for_mode(Md, Mode),
          {ok, #{status => 200, url => ResultUrl, title => Title, text => Text, content_type => tavily_content_type(Mode)}};
        {error, Reason} ->
          {error, Reason}
      end;
    {ok, {Status, _RespHeaders, RespBody}} ->
      {error, {tavily_extract_http_error, Status, openagentic_tool_webfetch_tavily_support:trim_bin(openagentic_tool_webfetch_sanitize:to_bin_safe_utf8(RespBody))}};
    {error, Reason} ->
      {error, Reason}
  end.

first_tavily_result(Obj0) ->
  Obj = openagentic_tool_webfetch_runtime:ensure_map(Obj0),
  Results =
    case maps:get(<<"results">>, Obj, []) of
      L when is_list(L) -> L;
      _ -> []
    end,
  first_tavily_result_loop(Results).

first_tavily_result_loop([]) -> {error, no_tavily_extract_result};
first_tavily_result_loop([El0 | Rest]) ->
  El = openagentic_tool_webfetch_runtime:ensure_map(El0),
  Url = string:trim(openagentic_tool_webfetch_runtime:to_bin(maps:get(<<"url">>, El, <<>>))),
  Title = string:trim(openagentic_tool_webfetch_runtime:to_bin(maps:get(<<"title">>, El, <<>>))),
  Md =
    openagentic_tool_webfetch_tavily_support:first_non_blank([
      maps:get(<<"raw_content">>, El, undefined),
      maps:get(<<"content">>, El, undefined),
      maps:get(<<"text">>, El, undefined)
    ]),
  case byte_size(openagentic_tool_webfetch_runtime:to_bin(Md)) > 0 of
    true -> {ok, #{url => Url, title => Title, markdown => openagentic_tool_webfetch_sanitize:normalize_markdown(openagentic_tool_webfetch_runtime:to_bin(Md))}};
    false -> first_tavily_result_loop(Rest)
  end.

tavily_content_type(Mode0) ->
  Mode = string:lowercase(string:trim(openagentic_tool_webfetch_runtime:to_bin(Mode0))),
  case Mode of
    <<"clean_html">> -> <<"text/html">>;
    <<"text">> -> <<"text/plain">>;
    _ -> <<"text/markdown">>
  end.
