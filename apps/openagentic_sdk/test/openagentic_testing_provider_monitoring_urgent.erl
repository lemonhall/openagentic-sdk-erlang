-module(openagentic_testing_provider_monitoring_urgent).

-behaviour(openagentic_provider).

-export([complete/1]).

complete(_Req) ->
  Payload =
    <<"```json\n",
      "{",
      "\"report_markdown\":\"# Monitoring Report\\n\\n## Summary\\nMajor escalation detected.\\n\\n## Facts\\n- Sanctions language shifted from stable to escalatory.\",",
      "\"result_summary\":\"Urgent monitoring completed\",",
      "\"alert_summary\":\"Major escalation detected\",",
      "\"report_kind\":\"urgent_fact_report\",",
      "\"observed_window\":{\"started_at\":1741435200.0,\"ended_at\":1741438800.0},",
      "\"facts\":[{",
      "\"title\":\"Sanctions language escalated\",",
      "\"fact_type\":\"sanctions_signal\",",
      "\"source\":\"Primary Source\",",
      "\"source_url\":\"https://example.com/urgent-source\",",
      "\"collection_method\":\"web_monitoring\",",
      "\"value_summary\":\"Official wording shifted to imminent restrictive action.\",",
      "\"change_summary\":\"Escalation language appeared in the latest statement.\",",
      "\"alert_level\":\"high\",",
      "\"confidence_note\":\"direct source\",",
      "\"evidence_refs\":[{\"kind\":\"url\",\"ref\":\"https://example.com/urgent-source\"}]",
      "}],",
      "\"artifacts\":[{",
      "\"title\":\"Urgent source page\",",
      "\"kind\":\"source_page\",",
      "\"summary\":\"Urgent source captured during the run\",",
      "\"path\":\"https://example.com/urgent-source\"",
      "}]",
      "}\n",
      "```">>,
  {ok, #{assistant_text => Payload, tool_calls => [], response_id => <<"resp_monitoring_urgent_1">>, usage => #{}}}.
