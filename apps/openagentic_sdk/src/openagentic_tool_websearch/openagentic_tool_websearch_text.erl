-module(openagentic_tool_websearch_text).

-export([html_unescape/1, tag_strip/1, urlencode/1]).

tag_strip(Html0) ->
  Html = openagentic_tool_websearch_utils:to_bin(Html0),
  re:replace(Html, <<"<.*?>">>, <<>>, [global, {return, binary}]).

html_unescape(S0) ->
  S1 = binary:replace(openagentic_tool_websearch_utils:to_bin(S0), <<"&amp;">>, <<"&">>, [global]),
  S2 = binary:replace(S1, <<"&lt;">>, <<"<">>, [global]),
  S3 = binary:replace(S2, <<"&gt;">>, <<">">>, [global]),
  S4 = binary:replace(S3, <<"&quot;">>, <<"\"">>, [global]),
  binary:replace(S4, <<"&#39;">>, <<"'">>, [global]).

urlencode(Bin0) ->
  %% Match java.net.URLEncoder (UTF-8) behavior used in Kotlin:
  %% - space becomes '+'
  %% - unreserved: ALPHA / DIGIT / '-' / '_' / '.' / '*'
  %% - everything else percent-encoded (uppercase hex)
  Bin = unicode:characters_to_binary(openagentic_tool_websearch_utils:to_bin(Bin0), utf8),
  iolist_to_binary([urlencode_byte(Byte) || <<Byte:8>> <= Bin]).

urlencode_byte($ ) -> $+;
urlencode_byte(Byte) when Byte >= $a, Byte =< $z -> Byte;
urlencode_byte(Byte) when Byte >= $A, Byte =< $Z -> Byte;
urlencode_byte(Byte) when Byte >= $0, Byte =< $9 -> Byte;
urlencode_byte($-) -> $-;
urlencode_byte($_) -> $_;
urlencode_byte($.) -> $.;
urlencode_byte($*) -> $*;
urlencode_byte(Byte) ->
  High = hex((Byte bsr 4) band 15),
  Low = hex(Byte band 15),
  [$%, High, Low].

hex(Nibble) when Nibble >= 0, Nibble =< 9 -> $0 + Nibble;
hex(Nibble) when Nibble >= 10, Nibble =< 15 -> $A + (Nibble - 10).
