-module(openagentic_case_store_run_urgent_brief).

-export([
  maybe_build_urgent_brief_mail/7,
  included_urgent_refs/1
]).

maybe_build_urgent_brief_mail(CaseId, Task0, Run0, Attempt0, FactReport0, Delivery0, Now) ->
  Delivery = openagentic_case_store_common_core:ensure_map(Delivery0),
  case is_urgent_delivery(Delivery) of
    false -> {undefined, undefined};
    true ->
      Task = openagentic_case_store_common_core:ensure_map(Task0),
      Run = openagentic_case_store_common_core:ensure_map(Run0),
      Attempt = openagentic_case_store_common_core:ensure_map(Attempt0),
      FactReport = openagentic_case_store_common_core:ensure_map(FactReport0),
      BriefId = openagentic_case_store_common_meta:new_id(<<"brief">>),
      Brief = #{header => openagentic_case_store_common_meta:header(BriefId, <<"urgent_brief">>, Now), links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, task_id => openagentic_case_store_common_meta:id_of(Task), run_id => openagentic_case_store_common_meta:id_of(Run), attempt_id => openagentic_case_store_common_meta:id_of(Attempt), report_id => openagentic_case_store_common_meta:id_of(FactReport), execution_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined)}), spec => openagentic_case_store_common_meta:compact_map(#{briefing_kind => <<"urgent_brief">>, title => <<"urgent monitoring brief">>, summary => openagentic_case_store_common_lookup:get_in_map(Task, [spec, title], <<"Untitled Task">>), alert_summary => openagentic_case_store_common_lookup:get_bin(Delivery, [alert_summary], <<"urgent alert">>), report_kind => openagentic_case_store_common_lookup:get_bin(Delivery, [report_kind], <<"urgent_fact_report">>), recommended_action => <<"review_reconsideration">>, fact_report_id => openagentic_case_store_common_meta:id_of(FactReport)}), state => #{status => <<"submitted">>, severity => <<"high">>, submitted_at => Now}, audit => #{issuer_role => <<"inspector">>}, ext => #{}},
      MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
      Mail = #{header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now), links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, related_object_refs => [#{type => <<"monitoring_task">>, id => openagentic_case_store_common_meta:id_of(Task)}, #{type => <<"monitoring_run">>, id => openagentic_case_store_common_meta:id_of(Run)}, #{type => <<"fact_report">>, id => openagentic_case_store_common_meta:id_of(FactReport)}, #{type => <<"urgent_brief">>, id => BriefId}], source_op_id => undefined, source_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined)}), spec => openagentic_case_store_common_meta:compact_map(#{message_type => <<"urgent_brief">>, title => <<"urgent monitoring brief">>, summary => openagentic_case_store_common_lookup:get_in_map(Task, [spec, title], <<"Untitled Task">>), recommended_action => <<"review">>, available_actions => [<<"review">>, <<"create_observation_pack">>], urgent_brief_id => BriefId, fact_report_id => openagentic_case_store_common_meta:id_of(FactReport)}), state => #{status => <<"unread">>, severity => <<"high">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined}, audit => #{issuer_role => <<"inspector">>}, ext => #{}},
      {Brief, Mail}
  end.

included_urgent_refs(Reports0) ->
  Reports = openagentic_case_store_common_core:ensure_list(Reports0),
  lists:filtermap(fun (Report0) -> Report = openagentic_case_store_common_core:ensure_map(Report0), case openagentic_case_store_common_lookup:get_in_map(Report, [links, urgent_brief_id], undefined) of undefined -> false; UrgentBriefId -> {true, openagentic_case_store_common_meta:compact_map(#{type => <<"urgent_brief">>, id => UrgentBriefId, report_id => openagentic_case_store_common_meta:id_of(Report), task_id => openagentic_case_store_common_lookup:get_in_map(Report, [links, task_id], undefined)})} end end, Reports).

is_urgent_delivery(Delivery) ->
  AlertSummary = openagentic_case_store_common_lookup:get_bin(Delivery, [alert_summary], <<>>),
  ReportKind = openagentic_case_store_common_lookup:get_bin(Delivery, [report_kind], <<"routine_fact_report">>),
  case ReportKind of
    <<"urgent_fact_report">> -> true;
    _ -> is_nonempty_alert(AlertSummary)
  end.

is_nonempty_alert(<<>>) -> false;
is_nonempty_alert(<<"No urgent alert">>) -> false;
is_nonempty_alert(_) -> true.
