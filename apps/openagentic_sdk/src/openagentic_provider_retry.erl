-module(openagentic_provider_retry).

-export([call/2, call/3, parse_retry_after_ms/2]).

call(Fun, RetryCfg0) -> openagentic_provider_retry_call:call(Fun, RetryCfg0).
call(Fun, RetryCfg0, Opts0) -> openagentic_provider_retry_call:call(Fun, RetryCfg0, Opts0).
parse_retry_after_ms(Header0, NowEpochMs0) -> openagentic_provider_retry_parse:parse_retry_after_ms(Header0, NowEpochMs0).
