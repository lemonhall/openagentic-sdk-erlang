-module(openagentic_case_store_run_failure_mail).
-export([build_exception_brief/7, build_task_run_failure_mail/8, build_rectification_mail/5, maybe_persist_mail/2]).

build_exception_brief(CaseId, Task0, Run0, Attempt0, FailureClass, FailureSummary, Now) ->
  Task = openagentic_case_store_common_core:ensure_map(Task0),
  Run = openagentic_case_store_common_core:ensure_map(Run0),
  Attempt = openagentic_case_store_common_core:ensure_map(Attempt0),
  BriefId = openagentic_case_store_common_meta:new_id(<<"brief">>),
  #{
    header => openagentic_case_store_common_meta:header(BriefId, <<"briefing">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          task_id => openagentic_case_store_common_meta:id_of(Task),
          run_id => openagentic_case_store_common_meta:id_of(Run),
          attempt_id => openagentic_case_store_common_meta:id_of(Attempt),
          execution_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined)
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          briefing_kind => <<"task_exception_brief">>,
          title => <<"task execution failed">>,
          summary => openagentic_case_store_common_lookup:get_in_map(Task, [spec, title], <<"Untitled Task">>),
          failure_class => FailureClass,
          failure_summary => FailureSummary,
          recommended_action => <<"review_and_rectify">>,
          scratch_ref => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, scratch_ref], undefined)
        }
      ),
    state => #{status => <<"submitted">>, severity => openagentic_case_store_run_failure_classify:exception_severity(FailureClass), submitted_at => Now},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

build_task_run_failure_mail(CaseId, Task0, Run0, Attempt0, ExceptionBrief0, FailureClass, FailureSummary, Now) ->
  Task = openagentic_case_store_common_core:ensure_map(Task0),
  Run = openagentic_case_store_common_core:ensure_map(Run0),
  Attempt = openagentic_case_store_common_core:ensure_map(Attempt0),
  ExceptionBrief = openagentic_case_store_common_core:ensure_map(ExceptionBrief0),
  MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
  #{
    header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now),
    links =>
      openagentic_case_store_common_meta:compact_map(
        #{
          case_id => CaseId,
          related_object_refs =>
            [
              #{type => <<"monitoring_task">>, id => openagentic_case_store_common_meta:id_of(Task)},
              #{type => <<"monitoring_run">>, id => openagentic_case_store_common_meta:id_of(Run)},
              #{type => <<"run_attempt">>, id => openagentic_case_store_common_meta:id_of(Attempt)},
              #{type => <<"briefing">>, id => openagentic_case_store_common_meta:id_of(ExceptionBrief)}
            ],
          source_op_id => undefined,
          source_session_id => openagentic_case_store_common_lookup:get_in_map(Attempt, [links, execution_session_id], undefined)
        }
      ),
    spec =>
      openagentic_case_store_common_meta:compact_map(
        #{
          message_type => <<"task_run_failed">>,
          title => <<"task run failed">>,
          summary => openagentic_case_store_common_lookup:get_in_map(Task, [spec, title], <<"Untitled Task">>),
          recommended_action => <<"review">>,
          available_actions => [<<"review">>, <<"rectify_task">>],
          failure_class => FailureClass,
          failure_summary => FailureSummary,
          exception_brief_id => openagentic_case_store_common_meta:id_of(ExceptionBrief)
        }
      ),
    state => #{status => <<"unread">>, severity => openagentic_case_store_run_failure_classify:exception_severity(FailureClass), acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

build_rectification_mail(CaseId, Task0, FailureClass, Count, Now) ->
  TaskId = openagentic_case_store_common_meta:id_of(Task0),
  Title = openagentic_case_store_common_lookup:get_in_map(Task0, [spec, title], <<"Untitled Task">>),
  MailId = openagentic_case_store_common_meta:new_id(<<"mail">>),
  #{
    header => openagentic_case_store_common_meta:header(MailId, <<"internal_mail">>, Now),
    links => openagentic_case_store_common_meta:compact_map(#{case_id => CaseId, related_object_refs => [#{type => <<"monitoring_task">>, id => TaskId}], source_op_id => undefined, source_session_id => undefined}),
    spec => #{message_type => <<"task_rectification_required">>, title => <<"task rectification required">>, summary => Title, recommended_action => <<"rectify_task">>, available_actions => [<<"review">>], failure_class => FailureClass, failure_count => Count},
    state => #{status => <<"unread">>, severity => <<"high">>, acted_at => undefined, acted_action => undefined, consumed_by_op_id => undefined},
    audit => #{issuer_role => <<"inspector">>},
    ext => #{}
  }.

maybe_persist_mail(_CaseDir, undefined) -> ok;
maybe_persist_mail(CaseDir, MailObj) -> openagentic_case_store_repo_persist:persist_case_object(CaseDir, openagentic_case_store_repo_paths:mail_file(CaseDir, openagentic_case_store_common_meta:id_of(MailObj)), MailObj).
