-module(openagentic_provider_protocol_test).

-include_lib("eunit/include/eunit.hrl").

normalize_protocol_test() ->
  ?assertEqual(responses, openagentic_provider_protocol:normalize(undefined)),
  ?assertEqual(responses, openagentic_provider_protocol:normalize(<<"">>)),
  ?assertEqual(responses, openagentic_provider_protocol:normalize(<<"RESPONSES">>)),
  ?assertEqual(responses, openagentic_provider_protocol:normalize(responses)),
  ?assertEqual(legacy, openagentic_provider_protocol:normalize(<<"LEGACY">>)),
  ?assertEqual(legacy, openagentic_provider_protocol:normalize(legacy)),
  ?assertEqual(legacy, openagentic_provider_protocol:normalize(<<"chat_completions">>)),
  ok.

