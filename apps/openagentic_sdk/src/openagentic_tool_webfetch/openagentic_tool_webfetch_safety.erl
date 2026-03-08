-module(openagentic_tool_webfetch_safety).

-export([validate_url/1]).

validate_url(Url0) ->
  Url = binary_to_list(openagentic_tool_webfetch_runtime:to_bin(Url0)),
  M = uri_string:parse(Url),
  Scheme0 = maps:get(scheme, M, ""),
  Scheme = string:lowercase(openagentic_tool_webfetch_runtime:to_bin(Scheme0)),
  case Scheme of
    <<"http">> -> ok;
    <<"https">> -> ok;
    _ -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: only http/https URLs are allowed">>})
  end,
  Host0 = maps:get(host, M, ""),
  Host = string:trim(openagentic_tool_webfetch_runtime:to_bin(Host0)),
  case byte_size(Host) > 0 of
    false -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: URL must include a hostname">>});
    true -> ok
  end,
  case is_blocked_host(Host) of
    true -> throw({kotlin_error, <<"IllegalArgumentException">>, <<"WebFetch: blocked hostname">>});
    false -> ok
  end.

is_blocked_host(Host0) ->
  Host = string:lowercase(openagentic_tool_webfetch_runtime:to_bin(Host0)),
  case Host of
    <<"localhost">> -> true;
    _ ->
      case openagentic_tool_webfetch_sanitize:ends_with(Host, <<".localhost">>) of
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
