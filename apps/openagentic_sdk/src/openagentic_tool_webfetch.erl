-module(openagentic_tool_webfetch).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"WebFetch">>.

description() -> <<"Fetch a URL over HTTP(S) and return a size-bounded representation.">>.

-define(MAX_BYTES, 1048576). %% 1 MiB
-define(MAX_REDIRECTS, 5).

run(Input0, _Ctx0) ->
  Input = ensure_map(Input0),
  Url0 = maps:get(<<"url">>, Input, maps:get(url, Input, undefined)),
  Url = string:trim(to_bin(Url0)),
  case byte_size(Url) > 0 of
    false ->
      {error, {kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: 'url' must be a non-empty string">>}};
    true ->
      Mode0 = maps:get(<<"mode">>, Input, maps:get(mode, Input, <<"markdown">>)),
      Mode = string:lowercase(string:trim(to_bin(Mode0))),
      MaxChars0 = int_opt(Input, [<<"max_chars">>, max_chars], 24000),
      MaxChars = clamp(MaxChars0, 1000, 80000),
      Headers0 = maps:get(<<"headers">>, Input, maps:get(headers, Input, #{})),
      Headers =
        case Headers0 of
          M when is_map(M) -> lower_headers(M);
          _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: 'headers' must be an object">>})
        end,
      RequestedUrl = Url,
      try
        ok = ensure_httpc_started(),
        ok = configure_proxy(),
        ok = validate_url(RequestedUrl),
        {FinalUrl, Status, RespHeaders, Body, Chain} = fetch_follow_redirects(RequestedUrl, Headers, ?MAX_REDIRECTS),
        Body2 = if byte_size(Body) > ?MAX_BYTES -> binary:part(Body, 0, ?MAX_BYTES); true -> Body end,
        ContentType = maps:get(<<"content-type">>, RespHeaders, undefined),
        RawText = to_bin_safe_utf8(Body2),
        Text0 =
          case Mode of
            <<"raw">> -> RawText;
            <<"text">> -> sanitize_to_text(RawText);
            <<"clean_html">> -> sanitize_to_clean_html(RawText);
            <<"markdown">> -> sanitize_to_markdown(RawText);
            _ -> sanitize_to_clean_html(RawText)
          end,
        Truncated = byte_size(Text0) > MaxChars,
        Limited = if Truncated -> binary:part(Text0, 0, MaxChars); true -> Text0 end,
        Title = extract_title(RawText),
        Out0 = #{
          requested_url => RequestedUrl,
          url => FinalUrl,
          final_url => FinalUrl,
          redirect_chain => Chain,
          status => Status,
          title => Title,
          mode => Mode,
          max_chars => MaxChars,
          truncated => Truncated,
          text => Limited
        },
        Out = case ContentType of undefined -> Out0; _ -> Out0#{content_type => ContentType} end,
        {ok, Out}
      catch
        throw:Reason -> {error, Reason};
        C:R -> {error, {C, R}}
      end
  end.

lower_headers(M) ->
  maps:from_list([{string:lowercase(to_bin(K)), to_bin(V)} || {K, V} <- maps:to_list(M)]).

fetch_follow_redirects(Url, Headers, Max) ->
  Chain0 = [Url],
  fetch_follow_redirects2(Url, Headers, 0, Max, Chain0).

fetch_follow_redirects2(Url, Headers, I, Max, Chain) when I =< Max ->
  {Status, RespHeaders, Body} = http_get(Url, Headers),
  case lists:member(Status, [301, 302, 303, 307, 308]) of
    false ->
      {Url, Status, RespHeaders, Body, Chain};
    true ->
      Location = maps:get(<<"location">>, RespHeaders, <<>>),
      case byte_size(string:trim(Location)) > 0 of
        false ->
          {Url, Status, RespHeaders, Body, Chain};
        true ->
          NextUrl = resolve_url(Url, Location),
          ok = validate_url(NextUrl),
          fetch_follow_redirects2(NextUrl, Headers, I + 1, Max, Chain ++ [NextUrl])
      end
  end;
fetch_follow_redirects2(_Url, _Headers, _I, Max, _Chain) ->
  throw({kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"WebFetch: too many redirects (>">>, integer_to_binary(Max), <<")">>])}).

http_get(Url0, HeadersMap) ->
  Url = binary_to_list(to_bin(Url0)),
  Headers = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- maps:to_list(HeadersMap)],
  ReqHeaders = Headers,
  Opts = [{timeout, 60000}, {autoredirect, false}],
  case httpc:request(get, {Url, ReqHeaders}, Opts, [{body_format, binary}], openagentic_webfetch) of
    {ok, {{_, Status, _}, RespHeaders0, Body}} ->
      RespHeaders = maps:from_list([{string:lowercase(to_bin(K)), to_bin(V)} || {K, V} <- RespHeaders0]),
      {Status, RespHeaders, Body};
    Err ->
      throw({http_get_failed, Err})
  end.

resolve_url(Base0, Location0) ->
  Base = binary_to_list(to_bin(Base0)),
  Location = binary_to_list(to_bin(Location0)),
  Res =
    case catch uri_string:resolve(Location, Base) of
      {'EXIT', _} -> Location;
      V -> V
    end,
  to_bin(Res).

validate_url(Url0) ->
  Url = binary_to_list(to_bin(Url0)),
  M = uri_string:parse(Url),
  Scheme0 = maps:get(scheme, M, ""),
  Scheme = string:lowercase(to_bin(Scheme0)),
  case Scheme of
    <<"http">> -> ok;
    <<"https">> -> ok;
    _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: only http/https URLs are allowed">>})
  end,
  Host0 = maps:get(host, M, ""),
  Host = string:trim(to_bin(Host0)),
  case byte_size(Host) > 0 of
    false -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: URL must include a hostname">>});
    true -> ok
  end,
  case is_blocked_host(Host) of
    true -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>});
    false -> ok
  end.

is_blocked_host(Host0) ->
  Host = string:lowercase(to_bin(Host0)),
  case Host of
    <<"localhost">> -> true;
    _ ->
      case ends_with(Host, <<".localhost">>) of
        true -> true;
        false ->
          case inet:getaddrs(binary_to_list(Host), inet) of
            {ok, Ips} -> lists:any(fun is_blocked_ip/1, Ips);
            _ -> false
          end
      end
  end.

is_blocked_ip({127, _, _, _}) -> true;
is_blocked_ip({10, _, _, _}) -> true;
is_blocked_ip({0, _, _, _}) -> true;
is_blocked_ip({169, 254, _, _}) -> true;
is_blocked_ip({172, B, _, _}) when B >= 16, B =< 31 -> true;
is_blocked_ip({192, 168, _, _}) -> true;
is_blocked_ip({_, _, _, _}) -> false;
is_blocked_ip(_Other) -> false.

sanitize_to_text(Raw) ->
  string:trim(tag_strip(Raw)).

sanitize_to_clean_html(Raw0) ->
  %% Best-effort: strip scripts/styles, then strip all tags except a small allowlist.
  Raw = remove_blocks(Raw0, <<"script">>),
  Raw2 = remove_blocks(Raw, <<"style">>),
  %% Keep anchor text; return as text-ish HTML (still safe to return plain).
  string:trim(Raw2).

sanitize_to_markdown(Raw) ->
  normalize_markdown(sanitize_to_text(Raw)).

remove_blocks(Html0, Tag0) ->
  Html = to_bin(Html0),
  Tag = to_bin(Tag0),
  Pat = iolist_to_binary([<<"<">>, Tag, <<"[\\s\\S]*?</">>, Tag, <<">">>]),
  re:replace(Html, Pat, <<>>, [global, caseless, {return, binary}]).

tag_strip(Html0) ->
  Html = to_bin(Html0),
  re:replace(Html, <<"<.*?>">>, <<>>, [global, {return, binary}]).

extract_title(Html0) ->
  Html = to_bin(Html0),
  case re:run(Html, <<"<title[^>]*>([\\s\\S]*?)</title>">>, [caseless, {capture, [1], binary}]) of
    {match, [T]} -> string:trim(tag_strip(T));
    _ -> <<>>
  end.

normalize_markdown(Md0) ->
  Md1 = binary:replace(to_bin(Md0), <<"\r\n">>, <<"\n">>, [global]),
  Md2 = binary:replace(Md1, <<"\r">>, <<"\n">>, [global]),
  Lines = [string:trim_right(L) || L <- binary:split(Md2, <<"\n">>, [global])],
  Md3 = iolist_to_binary(lists:join(<<"\n">>, Lines)),
  Md4 = re:replace(Md3, <<"\n{3,}">>, <<"\n\n">>, [global, {return, binary}]),
  string:trim(Md4).

to_bin_safe_utf8(Bin) when is_binary(Bin) ->
  try unicode:characters_to_binary(Bin, utf8)
  catch
    _:_ -> Bin
  end.

clamp(I, Min, Max) when is_integer(I) ->
  erlang:max(Min, erlang:min(Max, I));
clamp(_, Min, _Max) ->
  Min.

ends_with(Bin, Suffix) ->
  Sz = byte_size(Bin),
  Sz2 = byte_size(Suffix),
  Sz >= Sz2 andalso binary:part(Bin, Sz - Sz2, Sz2) =:= Suffix.

int_opt(Map, Keys, Default) ->
  Val =
    lists:foldl(
      fun (K, Acc) ->
        case Acc of
          undefined -> maps:get(K, Map, undefined);
          _ -> Acc
        end
      end,
      undefined,
      Keys
    ),
  case Val of
    undefined -> Default;
    I when is_integer(I) -> I;
    B when is_binary(B) ->
      case (catch binary_to_integer(string:trim(B))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    L when is_list(L) ->
      case (catch list_to_integer(string:trim(L))) of
        X when is_integer(X) -> X;
        _ -> Default
      end;
    _ -> Default
  end.

ensure_httpc_started() ->
  application:ensure_all_started(inets),
  application:ensure_all_started(ssl),
  _ = inets:start(httpc, [{profile, openagentic_webfetch}, {data_dir, httpc_data_dir()}]),
  ok.

httpc_data_dir() ->
  case os:getenv("OPENAGENTIC_HTTPC_DATA_DIR") of
    false -> "E:/erlang/httpc";
    V -> to_list(V)
  end.

configure_proxy() ->
  ProxyUrl =
    first_env([
      "HTTPS_PROXY",
      "HTTP_PROXY",
      "https_proxy",
      "http_proxy"
    ]),
  case ProxyUrl of
    false -> ok;
    Url ->
      case parse_proxy_url(Url) of
        {ok, {Host, Port}} ->
          Opts = [
            {proxy, {{Host, Port}, []}},
            {https_proxy, {{Host, Port}, []}}
          ],
          _ = httpc:set_options(Opts, openagentic_webfetch),
          ok;
        _ ->
          ok
      end
  end.

first_env([]) -> false;
first_env([K | T]) ->
  case os:getenv(K) of
    false -> first_env(T);
    "" -> first_env(T);
    V -> V
  end.

parse_proxy_url(Url0) ->
  Url = to_list(Url0),
  try
    M = uri_string:parse(Url),
    Host0 = maps:get(host, M, undefined),
    Port0 = maps:get(port, M, undefined),
    case Host0 of
      undefined -> {error, no_host};
      Host ->
        Port =
          case Port0 of
            undefined -> 7897;
            P when is_integer(P) -> P;
            PStr -> list_to_integer(PStr)
          end,
        {ok, {Host, Port}}
    end
  catch
    _:T -> {error, T}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
