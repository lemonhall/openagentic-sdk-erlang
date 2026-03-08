-module(openagentic_testing_provider_monitoring_success).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req) ->
  Payload =
    <<"```json\n",
      "{",
      "\"report_markdown\":\"# Monitoring Report\\n\\n## Summary\\nNo material deterioration observed.\\n\\n## Facts\\n- Diplomatic statement cadence remains stable.\",",
      "\"result_summary\":\"Routine monitoring completed\",",
      "\"alert_summary\":\"No urgent alert\",",
      "\"report_kind\":\"routine_fact_report\",",
      "\"observed_window\":{\"started_at\":1741435200.0,\"ended_at\":1741438800.0},",
      "\"facts\":[{",
      "\"title\":\"Diplomatic statement cadence remains stable\",",
      "\"fact_type\":\"diplomatic_statement\",",
      "\"source\":\"Primary Source\",",
      "\"source_url\":\"https://example.com/source\",",
      "\"collection_method\":\"web_monitoring\",",
      "\"value_summary\":\"Latest public statement keeps the prior wording pattern.\",",
      "\"change_summary\":\"No material escalation wording was observed.\",",
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
  {ok, #{assistant_text => Payload, tool_calls => [], response_id => <<"resp_monitoring_success_1">>, usage => #{}}}.
