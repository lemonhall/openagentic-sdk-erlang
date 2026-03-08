-module(openagentic_tool_websearch_domain).

-export([domain_allowed/3, ends_with/2]).

domain_allowed(Url0, Allowed0, Blocked0) ->
  Url = openagentic_tool_websearch_utils:to_bin(Url0),
  Allowed = [string:lowercase(openagentic_tool_websearch_utils:to_bin(D)) || D <- Allowed0],
  Blocked = [string:lowercase(openagentic_tool_websearch_utils:to_bin(D)) || D <- Blocked0],
  Host =
    try
      Parsed = uri_string:parse(binary_to_list(Url)),
      Host0 = maps:get(host, Parsed, ""),
      string:lowercase(openagentic_tool_websearch_utils:to_bin(Host0))
    catch
      _:_ -> <<>>
    end,
  case byte_size(Host) of
    0 -> Allowed =:= [];
    _ -> domain_allowed_for_host(Host, Allowed, Blocked)
  end.

domain_allowed_for_host(Host, Allowed, Blocked) ->
  case Blocked =/= [] andalso any_domain_match(Host, Blocked) of
    true -> false;
    false ->
      case Allowed =/= [] andalso not any_domain_match(Host, Allowed) of
        true -> false;
        false -> true
      end
  end.

any_domain_match(_Host, []) -> false;
any_domain_match(Host, [Domain | Rest]) ->
  Matches =
    Host =:= Domain orelse
      (binary:match(Host, <<".", Domain/binary>>) =/= nomatch andalso ends_with(Host, <<".", Domain/binary>>)),
  case Matches of
    true -> true;
    false -> any_domain_match(Host, Rest)
  end.

ends_with(Bin, Suffix) ->
  BinSize = byte_size(Bin),
  SuffixSize = byte_size(Suffix),
  BinSize >= SuffixSize andalso binary:part(Bin, BinSize - SuffixSize, SuffixSize) =:= Suffix.
