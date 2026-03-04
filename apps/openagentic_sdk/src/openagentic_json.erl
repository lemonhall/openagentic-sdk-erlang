-module(openagentic_json).

-export([encode/1, decode/1]).

encode(Map) ->
  jsone:encode(Map).

decode(Bin) when is_binary(Bin) ->
  jsone:decode(Bin, [{object_format, map}]).

