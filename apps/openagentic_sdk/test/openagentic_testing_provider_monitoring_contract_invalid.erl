-module(openagentic_testing_provider_monitoring_contract_invalid).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req) ->
  Payload =
    <<"```json\n",
      "{",
      "\"report_markdown\":\"# Monitoring Report\\n\\n## Summary\\nOnly the summary section is present.\",",
      "\"result_summary\":\"Contract should reject this delivery\",",
      "\"facts\":[{",
      "\"title\":\"Reference fact\",",
      "\"fact_type\":\"observation\",",
      "\"source\":\"Primary Source\",",
      "\"source_url\":\"https://example.com/source\",",
      "\"collection_method\":\"web_monitoring\",",
      "\"value_summary\":\"Observed a routine update.\",",
      "\"change_summary\":\"No major change.\",",
      "\"alert_level\":\"normal\",",
      "\"confidence_note\":\"direct source\",",
      "\"evidence_refs\":[{\"kind\":\"url\",\"ref\":\"https://example.com/source\"}]",
      "}],",
      "\"artifacts\":[{",
      "\"title\":\"Primary source page\",",
      "\"kind\":\"source_page\",",
      "\"summary\":\"Primary source captured during the run\",",
      "\"path\":\"https://example.com/source\"",
      "}]",
      "}\n",
      "```">>,
  {ok, #{assistant_text => Payload, tool_calls => [], response_id => <<"resp_monitoring_contract_invalid_1">>, usage => #{}}}.
