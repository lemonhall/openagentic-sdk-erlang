-module(openagentic_tool_webfetch_api).

-export([run/2, lower_headers/1]).

-define(MAX_BYTES, 1048576).
-define(MAX_REDIRECTS, 5).

run(Input0, Ctx0) ->
  Input = openagentic_tool_webfetch_runtime:ensure_map(Input0),
  Ctx = openagentic_tool_webfetch_runtime:ensure_map(Ctx0),
  Url0 = maps:get(<<"url">>, Input, maps:get(url, Input, undefined)),
  Url = string:trim(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  case byte_size(Url) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: 'url' must be a non-empty string">>}};
    true ->
      Mode0 = maps:get(<<"mode">>, Input, maps:get(mode, Input, <<"markdown">>)),
      Mode = string:lowercase(string:trim(openagentic_tool_webfetch_runtime:to_bin(Mode0))),
      MaxChars0 = openagentic_tool_webfetch_runtime:int_opt(Input, [<<"max_chars">>, max_chars], 24000),
      MaxChars = openagentic_tool_webfetch_sanitize:clamp(MaxChars0, 1000, 80000),
      Headers0 = maps:get(<<"headers">>, Input, maps:get(headers, Input, #{})),
      Headers =
        case Headers0 of
          M when is_map(M) -> lower_headers(M);
          _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: 'headers' must be an object">>})
        end,
      RequestedUrl = Url,
      try
        ok = openagentic_tool_webfetch_runtime:ensure_httpc_started(),
        ok = openagentic_tool_webfetch_runtime:configure_proxy(),
        ok = openagentic_tool_webfetch_safety:validate_url(RequestedUrl),
        Transport = maps:get(webfetch_transport, Ctx, undefined),
        {FinalUrl, Status, RespHeaders, Body, Chain} = openagentic_tool_webfetch_request:fetch_follow_redirects(RequestedUrl, Headers, ?MAX_REDIRECTS, Transport),
        Body2 = if byte_size(Body) > ?MAX_BYTES -> binary:part(Body, 0, ?MAX_BYTES); true -> Body end,
        RawText = openagentic_tool_webfetch_sanitize:to_bin_safe_utf8(Body2),
        Text0 =
          case Mode of
            <<"raw">> -> RawText;
            <<"text">> -> openagentic_tool_webfetch_sanitize:sanitize_to_text(RawText, FinalUrl);
            <<"clean_html">> -> openagentic_tool_webfetch_sanitize:sanitize_to_clean_html(RawText, FinalUrl);
            <<"markdown">> -> openagentic_tool_webfetch_sanitize:sanitize_to_markdown(RawText, FinalUrl);
            _ -> openagentic_tool_webfetch_sanitize:sanitize_to_clean_html(RawText, FinalUrl)
          end,
        Title0 = openagentic_tool_webfetch_sanitize:extract_title(RawText),
        Extra = openagentic_tool_webfetch_tavily:maybe_tavily_extract(RequestedUrl, FinalUrl, Status, RespHeaders, RawText, Text0, Mode, Ctx),
        Out = build_output(RequestedUrl, FinalUrl, Chain, Status, Title0, Mode, MaxChars, Text0, RespHeaders, Extra),
        {ok, Out}
      catch
        throw:Reason -> {error, Reason};
        C:R -> {error, {C, R}}
      end
  end.

lower_headers(M) ->
  maps:from_list([{string:lowercase(openagentic_tool_webfetch_runtime:to_bin(K)), openagentic_tool_webfetch_runtime:to_bin(V)} || {K, V} <- maps:to_list(M)]).

build_output(RequestedUrl, FinalUrl, Chain, Status0, Title0, Mode, MaxChars, Text0, RespHeaders0, Extra0) ->
  RespHeaders = openagentic_tool_webfetch_runtime:ensure_map(RespHeaders0),
  Extra = openagentic_tool_webfetch_runtime:ensure_map(Extra0),
  Status = maps:get(status, Extra, Status0),
  Title = maps:get(title, Extra, Title0),
  Text = maps:get(text, Extra, Text0),
  Url = maps:get(url, Extra, FinalUrl),
  FinalUrl2 = maps:get(final_url, Extra, FinalUrl),
  Truncated = byte_size(Text) > MaxChars,
  Limited = if Truncated -> binary:part(Text, 0, MaxChars); true -> Text end,
  Out0 = #{
    requested_url => RequestedUrl,
    url => Url,
    final_url => FinalUrl2,
    redirect_chain => Chain,
    status => Status,
    title => Title,
    mode => Mode,
    max_chars => MaxChars,
    truncated => Truncated,
    text => Limited
  },
  ContentType = maps:get(content_type, Extra, maps:get(<<"content-type">>, RespHeaders, undefined)),
  Out1 = case ContentType of undefined -> Out0; _ -> Out0#{content_type => ContentType} end,
  maps:merge(Out1, maps:without([status, title, text, url, final_url, content_type], Extra)).
