-module(openagentic_tool_webfetch).

-behaviour(openagentic_tool).

-export([name/0, description/0, run/2]).

name() -> <<"WebFetch">>.

description() -> <<"Fetch a URL over HTTP(S) and return a size-bounded representation.">>.

-define(MAX_BYTES, 1048576). %% 1 MiB
-define(MAX_REDIRECTS, 5).

run(Input0, Ctx0) ->
  Input = ensure_map(Input0),
  Ctx = ensure_map(Ctx0),
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
        Transport = maps:get(webfetch_transport, Ctx, undefined),
        {FinalUrl, Status, RespHeaders, Body, Chain} = fetch_follow_redirects(RequestedUrl, Headers, ?MAX_REDIRECTS, Transport),
        Body2 = if byte_size(Body) > ?MAX_BYTES -> binary:part(Body, 0, ?MAX_BYTES); true -> Body end,
        ContentType = maps:get(<<"content-type">>, RespHeaders, undefined),
        RawText = to_bin_safe_utf8(Body2),
        Text0 =
          case Mode of
            <<"raw">> -> RawText;
            <<"text">> -> sanitize_to_text(RawText, FinalUrl);
            <<"clean_html">> -> sanitize_to_clean_html(RawText, FinalUrl);
            <<"markdown">> -> sanitize_to_markdown(RawText, FinalUrl);
            _ -> sanitize_to_clean_html(RawText, FinalUrl)
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

fetch_follow_redirects(Url, Headers, Max, Transport) ->
  Chain0 = [Url],
  fetch_follow_redirects2(Url, Headers, Transport, 0, Max, Chain0).

fetch_follow_redirects2(Url, Headers, Transport, I, Max, Chain) when I =< Max ->
  {Status, RespHeaders, Body} = http_get(Url, Headers, Transport),
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
          fetch_follow_redirects2(NextUrl, Headers, Transport, I + 1, Max, Chain ++ [NextUrl])
      end
  end;
fetch_follow_redirects2(_Url, _Headers, _Transport, _I, Max, _Chain) ->
  throw({kotlin_error, <<"IllegalArgumentException">>, iolist_to_binary([<<"WebFetch: too many redirects (>">>, integer_to_binary(Max), <<")">>])}).

http_get(Url0, HeadersMap, Transport) when is_function(Transport, 2) ->
  Url = to_bin(Url0),
  case Transport(Url, HeadersMap) of
    {ok, {Status, RespHeaders, Body}} ->
      {Status, lower_headers(ensure_map(RespHeaders)), to_bin(Body)};
    {error, Reason} ->
      throw({http_get_failed, Reason});
    Other ->
      throw({http_get_failed, Other})
  end;
http_get(Url0, HeadersMap, _Transport) ->
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
          Ips4 =
            case inet:getaddrs(binary_to_list(Host), inet) of
              {ok, Ips4List} -> Ips4List;
              _ -> []
            end,
          Ips6 =
            case inet:getaddrs(binary_to_list(Host), inet6) of
              {ok, Ips6List} -> Ips6List;
              _ -> []
            end,
          lists:any(fun is_blocked_ip/1, Ips4 ++ Ips6)
      end
  end.

is_blocked_ip({127, _, _, _}) -> true;
is_blocked_ip({10, _, _, _}) -> true;
is_blocked_ip({0, _, _, _}) -> true;
is_blocked_ip({169, 254, _, _}) -> true;
is_blocked_ip({172, B, _, _}) when B >= 16, B =< 31 -> true;
is_blocked_ip({192, 168, _, _}) -> true;
%% IPv6
is_blocked_ip({0, 0, 0, 0, 0, 0, 0, 0}) -> true; %% unspecified
is_blocked_ip({0, 0, 0, 0, 0, 0, 0, 1}) -> true; %% loopback
is_blocked_ip({H1, _, _, _, _, _, _, _}) when is_integer(H1), H1 >= 16#FE80, H1 =< 16#FEBF -> true; %% link-local fe80::/10
is_blocked_ip({H1, _, _, _, _, _, _, _}) when is_integer(H1), H1 >= 16#FC00, H1 =< 16#FDFF -> true; %% unique-local fc00::/7
is_blocked_ip({H1, _, _, _, _, _, _, _}) when is_integer(H1), H1 >= 16#FEC0, H1 =< 16#FEFF -> true; %% site-local fec0::/10 (deprecated)
%% IPv4-mapped IPv6 ::ffff:a.b.c.d
is_blocked_ip({0, 0, 0, 0, 0, 16#FFFF, Hi, Lo}) when is_integer(Hi), is_integer(Lo) ->
  A = (Hi bsr 8) band 255,
  B = Hi band 255,
  C = (Lo bsr 8) band 255,
  D = Lo band 255,
  is_blocked_ip({A, B, C, D});
is_blocked_ip({_, _, _, _}) -> false;
is_blocked_ip(_Other) -> false.

sanitize_to_text(Raw0, _BaseUrl) ->
  Raw = strip_boilerplate(Raw0),
  string:trim(html_unescape(tag_strip(Raw))).

sanitize_to_clean_html(Raw0, BaseUrl0) ->
  BaseUrl = to_bin(BaseUrl0),
  Raw = strip_boilerplate(Raw0),
  Content0 = select_main_content(Raw),
  Content1 = prune_non_content_blocks(Content0),
  Html0 = sanitize_allowlist(Content1, BaseUrl),
  Html1 = prune_empty_nodes(Html0),
  Html2 = format_block_separators(Html1),
  string:trim(Html2).

sanitize_to_markdown(Raw0, BaseUrl0) ->
  Html = sanitize_to_clean_html(Raw0, BaseUrl0),
  Md0 = html_to_markdown(Html, BaseUrl0),
  normalize_markdown(Md0).

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
  Lines = [string:trim(L, trailing) || L <- binary:split(Md2, <<"\n">>, [global])],
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

strip_boilerplate(Html0) ->
  Html = to_bin(Html0),
  Tags = [
    <<"script">>, <<"style">>, <<"noscript">>, <<"svg">>, <<"canvas">>,
    <<"iframe">>, <<"video">>, <<"audio">>, <<"picture">>, <<"source">>,
    <<"header">>, <<"footer">>, <<"nav">>, <<"aside">>, <<"form">>, <<"button">>
  ],
  Html1 = lists:foldl(fun (Tag, AccHtml) -> remove_blocks(AccHtml, Tag) end, Html, Tags),
  Html2 = remove_role_blocks(Html1),
  Html3 = remove_attr_blocks(Html2, [<<"cookie">>, <<"consent">>, <<"advert">>, <<"ad-">>, <<"ads">>]),
  Html3.

remove_role_blocks(Html0) ->
  Html = to_bin(Html0),
  Pat = <<"<([a-zA-Z0-9]+)[^>]*\\brole\\s*=\\s*\\\"(banner|navigation|contentinfo|complementary)\\\"[^>]*>[\\s\\S]*?</\\1>">>,
  re:replace(Html, Pat, <<>>, [global, caseless, dotall, {return, binary}]).

remove_attr_blocks(Html0, Tokens) ->
  lists:foldl(
    fun (Tok0, Acc0) ->
      Tok = to_bin(Tok0),
      Pat =
        iolist_to_binary([
          <<"<([a-zA-Z0-9]+)[^>]*(?:class|id)\\s*=\\s*\\\"[^\\\"]*">>,
          Tok,
          <<"[^\\\"]*\\\"[^>]*>[\\s\\S]*?</\\1>">>
        ]),
      re:replace(Acc0, Pat, <<>>, [global, caseless, dotall, {return, binary}])
    end,
    to_bin(Html0),
    Tokens
  ).

select_main_content(Html0) ->
  Html = to_bin(Html0),
  case extract_first_tag(Html, <<"article">>) of
    {ok, V} -> V;
    _ ->
      case extract_first_tag(Html, <<"main">>) of
        {ok, V2} -> V2;
        _ ->
          case extract_first_tag(Html, <<"body">>) of
            {ok, V3} -> V3;
            _ -> Html
          end
      end
  end.

extract_first_tag(Html0, Tag0) ->
  Html = to_bin(Html0),
  Tag = to_list(Tag0),
  Pat = iolist_to_binary([<<"<">>, Tag, <<"\\b[^>]*>[\\s\\S]*?</">>, Tag, <<">">>]),
  case re:run(Html, Pat, [caseless, dotall, {capture, first, binary}]) of
    {match, [M]} -> {ok, M};
    _ -> {error, not_found}
  end.

prune_non_content_blocks(Html0) ->
  remove_attr_blocks(Html0, [
    <<"breadcrumb">>, <<"share">>, <<"social">>, <<"comment">>,
    <<"author">>, <<"byline">>, <<"newsletter">>, <<"subscribe">>, <<"promo">>
  ]).

sanitize_allowlist(Html0, BaseUrl0) ->
  BaseUrl = to_bin(BaseUrl0),
  Html1 = re:replace(to_bin(Html0), <<"<img\\b[^>]*>">>, <<>>, [global, caseless, {return, binary}]),
  Html2 = sanitize_anchor_open_tags(Html1, BaseUrl),
  Html3 = strip_attrs_for_allowed(Html2),
  Html4 = filter_disallowed_tags(Html3),
  Html4.

sanitize_anchor_open_tags(Html0, BaseUrl0) ->
  BaseUrl = to_bin(BaseUrl0),
  Html = to_bin(Html0),
  Pat = <<"<a\\b[^>]*>">>,
  sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, 0, []).

sanitize_anchor_open_tags_loop(Html, _BaseUrl, _Pat, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, Pos0, AccRev) ->
  case re:run(Html, Pat, [caseless, {capture, first, binary}, {offset, Pos0}]) of
    {match, [Tag]} ->
      {Start, Len} = match_span(Html, Pat, Pos0),
      PrefixLen = Start - Pos0,
      Prefix = binary:part(Html, Pos0, PrefixLen),
      Tag2 = sanitize_one_anchor_tag(Tag, BaseUrl),
      NewPos = Start + Len,
      sanitize_anchor_open_tags_loop(Html, BaseUrl, Pat, NewPos, [Tag2, Prefix | AccRev]);
    _ ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]))
  end.

match_span(Html, Pat, Pos0) ->
  {match, [{Start, Len}]} = re:run(Html, Pat, [caseless, {capture, first, index}, {offset, Pos0}]),
  {Start, Len}.

sanitize_one_anchor_tag(Tag0, BaseUrl0) ->
  Tag = to_bin(Tag0),
  BaseUrl = to_bin(BaseUrl0),
  Href0 = extract_attr(Tag, <<"href">>),
  Title0 = extract_attr(Tag, <<"title">>),
  Href =
    case Href0 of
      undefined -> undefined;
      <<>> -> undefined;
      HrefVal -> resolve_url_bin(BaseUrl, HrefVal)
    end,
  Title =
    case Title0 of
      undefined -> undefined;
      <<>> -> undefined;
      TitleVal -> TitleVal
    end,
  build_anchor_tag(Href, Title).

build_anchor_tag(undefined, undefined) ->
  <<"<a>">>;
build_anchor_tag(Href, undefined) ->
  iolist_to_binary([<<"<a href=\"">>, Href, <<"\">">>]);
build_anchor_tag(undefined, Title) ->
  iolist_to_binary([<<"<a title=\"">>, escape_attr(Title), <<"\">">>]);
build_anchor_tag(Href, Title) ->
  iolist_to_binary([<<"<a href=\"">>, Href, <<"\" title=\"">>, escape_attr(Title), <<"\">">>]).

escape_attr(Bin0) ->
  Bin = to_bin(Bin0),
  Bin1 = binary:replace(Bin, <<"&">>, <<"&amp;">>, [global]),
  Bin2 = binary:replace(Bin1, <<"\"">>, <<"&quot;">>, [global]),
  Bin2.

extract_attr(Tag0, Attr0) ->
  Tag = to_bin(Tag0),
  Attr = to_list(Attr0),
  Pat =
    iolist_to_binary([
      <<"\\b">>, Attr, <<"\\s*=\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([^\\s>]+))">>
    ]),
  case re:run(Tag, Pat, [caseless, dotall, {capture, [1, 2, 3], binary}]) of
    {match, [V1, V2, V3]} ->
      first_non_empty_bin([V1, V2, V3]);
    _ ->
      undefined
  end.

first_non_empty_bin([]) -> undefined;
first_non_empty_bin([H | T]) ->
  case H of
    undefined -> first_non_empty_bin(T);
    <<>> -> first_non_empty_bin(T);
    _ -> H
  end.

resolve_url_bin(Base0, Rel0) ->
  Base = binary_to_list(to_bin(Base0)),
  Rel = binary_to_list(to_bin(Rel0)),
  try
    to_bin(uri_string:resolve(Rel, Base))
  catch
    _:_ ->
      to_bin(Rel0)
  end.

strip_attrs_for_allowed(Html0) ->
  Html = to_bin(Html0),
  Tags = [
    <<"p">>, <<"br">>, <<"ul">>, <<"ol">>, <<"li">>,
    <<"table">>, <<"thead">>, <<"tbody">>, <<"tr">>, <<"td">>, <<"th">>,
    <<"h1">>, <<"h2">>, <<"h3">>, <<"h4">>, <<"h5">>, <<"h6">>,
    <<"pre">>, <<"code">>, <<"blockquote">>, <<"em">>, <<"strong">>
  ],
  lists:foldl(
    fun (T0, Acc0) ->
      T = to_list(T0),
      Pat = iolist_to_binary([<<"<(">>, T, <<")\\b[^>]*>">>]),
      re:replace(Acc0, Pat, <<"<\\1>">>, [global, caseless, {return, binary}])
    end,
    Html,
    Tags
  ).

filter_disallowed_tags(Html0) ->
  Html = to_bin(Html0),
  Allowed = allowed_tags_set(),
  filter_tags_loop(Html, Allowed, 0, []).

allowed_tags_set() ->
  #{<<"a">> => true, <<"p">> => true, <<"br">> => true,
    <<"ul">> => true, <<"ol">> => true, <<"li">> => true,
    <<"table">> => true, <<"thead">> => true, <<"tbody">> => true, <<"tr">> => true, <<"td">> => true, <<"th">> => true,
    <<"h1">> => true, <<"h2">> => true, <<"h3">> => true, <<"h4">> => true, <<"h5">> => true, <<"h6">> => true,
    <<"pre">> => true, <<"code">> => true, <<"blockquote">> => true, <<"em">> => true, <<"strong">> => true}.

filter_tags_loop(Html, _Allowed, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
filter_tags_loop(Html, Allowed, Pos0, AccRev) ->
  case binary:match(Html, <<"<">>, [{scope, {Pos0, byte_size(Html) - Pos0}}]) of
    nomatch ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]));
    {P, _} ->
      Prefix = binary:part(Html, Pos0, P - Pos0),
      case binary:match(Html, <<">">>, [{scope, {P, byte_size(Html) - P}}]) of
        nomatch ->
          Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
          iolist_to_binary(lists:reverse([Tail | AccRev]));
        {Q, _} ->
          Tag = binary:part(Html, P, Q - P + 1),
          Name = tag_name_lower(Tag),
          Keep = maps:get(Name, Allowed, false),
          Next = Q + 1,
          case Keep of
            true -> filter_tags_loop(Html, Allowed, Next, [Tag, Prefix | AccRev]);
            false -> filter_tags_loop(Html, Allowed, Next, [Prefix | AccRev])
          end
      end
  end.

tag_name_lower(Tag0) ->
  Tag = to_bin(Tag0),
  T1 = binary:part(Tag, 1, byte_size(Tag) - 1),
  T2 =
    case T1 of
      <<"/", Rest/binary>> -> Rest;
      _ -> T1
    end,
  %% name ends at first space or '>' or '/'
  Name0 = take_while_name(T2, 0),
  string:lowercase(to_bin(Name0)).

take_while_name(Bin, I) ->
  Size = byte_size(Bin),
  take_while_name2(Bin, I, Size).

take_while_name2(_Bin, I, Size) when I >= Size -> <<>>;
take_while_name2(Bin, I, Size) ->
  C = binary:at(Bin, I),
  case (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z) orelse (C >= $0 andalso C =< $9) of
    true ->
      <<C, (take_while_name2(Bin, I + 1, Size))/binary>>;
    false ->
      <<>>
  end.

prune_empty_nodes(Html0) ->
  Html = to_bin(Html0),
  Tags = [<<"div">>, <<"span">>, <<"p">>, <<"section">>, <<"article">>, <<"main">>, <<"blockquote">>,
          <<"ul">>, <<"ol">>, <<"li">>, <<"table">>, <<"thead">>, <<"tbody">>, <<"tr">>, <<"td">>, <<"th">>],
  prune_empty_nodes_passes(Html, Tags, 0, 10).

prune_empty_nodes_passes(Html, _Tags, Pass, MaxPasses) when Pass >= MaxPasses ->
  Html;
prune_empty_nodes_passes(Html0, Tags, Pass, MaxPasses) ->
  Html = lists:foldl(
    fun (T0, Acc0) ->
      T = to_list(T0),
      Pat = iolist_to_binary([<<"<">>, T, <<">\\s*</">>, T, <<">">>]),
      re:replace(Acc0, Pat, <<>>, [global, caseless, dotall, {return, binary}])
    end,
    Html0,
    Tags
  ),
  case Html =:= Html0 of
    true -> Html;
    false -> prune_empty_nodes_passes(Html, Tags, Pass + 1, MaxPasses)
  end.

format_block_separators(Html0) ->
  Html = to_bin(Html0),
  Pat = <<">\\s*(?=<(h[1-6]|p|ul|ol|li|table|thead|tbody|tr|td|th|pre|blockquote)\\b)">>,
  re:replace(Html, Pat, <<">\n">>, [global, caseless, {return, binary}]).

html_to_markdown(Html0, BaseUrl0) ->
  BaseUrl = to_bin(BaseUrl0),
  Html = to_bin(Html0),
  S1 = convert_heading(Html, 1),
  S2 = convert_heading(S1, 2),
  S3 = convert_heading(S2, 3),
  S4 = convert_heading(S3, 4),
  S5 = convert_heading(S4, 5),
  S6 = convert_heading(S5, 6),
  S7 = convert_links_md(S6, BaseUrl),
  S8 = re:replace(S7, <<"<br\\s*/?>">>, <<"\n">>, [global, caseless, {return, binary}]),
  S9 = re:replace(S8, <<"</p>">>, <<"\n\n">>, [global, caseless, {return, binary}]),
  S10 = re:replace(S9, <<"<p>">>, <<>>, [global, caseless, {return, binary}]),
  S11 = re:replace(S10, <<"<li>">>, <<"- ">>, [global, caseless, {return, binary}]),
  S12 = re:replace(S11, <<"</li>">>, <<"\n">>, [global, caseless, {return, binary}]),
  S13 = re:replace(S12, <<"</?(ul|ol)>">>, <<"\n">>, [global, caseless, {return, binary}]),
  Text = html_unescape(tag_strip(S13)),
  Text.

convert_heading(Html0, N) ->
  Tag = iolist_to_binary([<<"h">>, integer_to_binary(N)]),
  Pat = iolist_to_binary([<<"<">>, Tag, <<">([\\s\\S]*?)</">>, Tag, <<">">>]),
  Prefix = lists:duplicate(N, $#),
  Repl = iolist_to_binary([Prefix, <<" \\1\n\n">>]),
  re:replace(to_bin(Html0), Pat, Repl, [global, caseless, dotall, {return, binary}]).

convert_links_md(Html0, BaseUrl0) ->
  BaseUrl = to_bin(BaseUrl0),
  Html = to_bin(Html0),
  Pat = <<"<a\\b[^>]*>([\\s\\S]*?)</a>">>,
  convert_links_md_loop(Html, BaseUrl, Pat, 0, []).

convert_links_md_loop(Html, _BaseUrl, _Pat, Pos, AccRev) when Pos >= byte_size(Html) ->
  iolist_to_binary(lists:reverse(AccRev));
convert_links_md_loop(Html, BaseUrl, Pat, Pos0, AccRev) ->
  case re:run(Html, Pat, [caseless, dotall, {capture, [0, 1], binary}, {offset, Pos0}]) of
    {match, [Full, Inner]} ->
      {Start, Len} = match_span(Html, Pat, Pos0),
      Prefix = binary:part(Html, Pos0, Start - Pos0),
      Href0 = extract_attr(Full, <<"href">>),
      Href =
        case Href0 of
          undefined -> <<>>;
          <<>> -> <<>>;
          V -> resolve_url_bin(BaseUrl, V)
        end,
      Text = string:trim(html_unescape(tag_strip(Inner))),
      Md =
        case {byte_size(Text) > 0, byte_size(Href) > 0} of
          {true, true} -> iolist_to_binary([<<"[">>, Text, <<"](">>, Href, <<")">>]);
          {true, false} -> Text;
          _ -> <<>>
        end,
      NewPos = Start + Len,
      convert_links_md_loop(Html, BaseUrl, Pat, NewPos, [Md, Prefix | AccRev]);
    _ ->
      Tail = binary:part(Html, Pos0, byte_size(Html) - Pos0),
      iolist_to_binary(lists:reverse([Tail | AccRev]))
  end.

html_unescape(S0) ->
  S1 = binary:replace(to_bin(S0), <<"&amp;">>, <<"&">>, [global]),
  S2 = binary:replace(S1, <<"&lt;">>, <<"<">>, [global]),
  S3 = binary:replace(S2, <<"&gt;">>, <<">">>, [global]),
  S4 = binary:replace(S3, <<"&quot;">>, <<"\"">>, [global]),
  binary:replace(S4, <<"&#39;">>, <<"'">>, [global]).
