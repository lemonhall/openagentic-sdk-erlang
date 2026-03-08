-module(openagentic_case_store_candidates_infer).
-export([template_candidate_spec/3, resolve_round_id/3, newest_round_id/1, infer_candidate_specs_from_session/3, latest_text_candidate/1, infer_candidate_specs_from_text/2, candidate_like_line/1, candidate_spec_from_line/2, shorten_title/1]).

template_candidate_spec(TemplateObj0, Input0, CaseObj) ->
  TemplateObj = openagentic_case_store_common_core:ensure_map(TemplateObj0),
  Input = openagentic_case_store_common_core:ensure_map(Input0),
  TemplateSpec = openagentic_case_store_common_core:ensure_map(maps:get(spec, TemplateObj, #{})),
  TemplateSummary = openagentic_case_store_common_lookup:get_bin(TemplateSpec, [summary], undefined),
  DefaultTimezone = openagentic_case_store_common_lookup:get_bin(TemplateSpec, [default_timezone, defaultTimezone], openagentic_case_store_common_meta:default_timezone(CaseObj)),
  maps:merge(
    TemplateSpec,
    openagentic_case_store_common_meta:compact_map(
      #{
        title => openagentic_case_store_common_lookup:get_bin(Input, [title], openagentic_case_store_common_lookup:get_in_map(TemplateSpec, [title], <<"Untitled Candidate">>)),
        objective => openagentic_case_store_common_lookup:get_bin(Input, [objective], openagentic_case_store_common_lookup:get_in_map(TemplateSpec, [objective], undefined)),
        default_timezone => openagentic_case_store_common_lookup:get_bin(Input, [default_timezone, defaultTimezone], DefaultTimezone),
        extracted_summary => openagentic_case_store_common_lookup:get_bin(Input, [summary], TemplateSummary)
      }
    )
  ).

resolve_round_id(CaseDir, Input, CaseObj) ->
  case openagentic_case_store_common_lookup:get_bin(Input, [round_id, roundId], undefined) of
    undefined -> openagentic_case_store_common_lookup:get_in_map(CaseObj, [links, current_round_id], newest_round_id(CaseDir));
    Value -> Value
  end.

newest_round_id(CaseDir) ->
  Rounds = openagentic_case_store_repo_readers:sort_by_created_at(openagentic_case_store_repo_readers:read_objects_in_dir(filename:join([CaseDir, "meta", "rounds"]))),
  case lists:reverse(Rounds) of
    [Round | _] -> openagentic_case_store_common_meta:id_of(Round);
    [] -> throw({error, round_not_found})
  end.

infer_candidate_specs_from_session(RootDir, WorkflowSessionId0, DefaultTimezone) ->
  WorkflowSessionId = openagentic_case_store_common_core:ensure_list(WorkflowSessionId0),
  Events = openagentic_session_store:read_events(RootDir, WorkflowSessionId),
  Text = latest_text_candidate(Events),
  infer_candidate_specs_from_text(Text, DefaultTimezone).

latest_text_candidate(Events) ->
  lists:foldl(
    fun (Event0, Best0) ->
      Event = openagentic_case_store_common_core:ensure_map(Event0),
      Type = openagentic_case_store_common_lookup:get_bin(Event, [type], <<>>),
      Candidate =
        case Type of
          <<"workflow.done">> -> openagentic_case_store_common_lookup:get_bin(Event, [final_text], <<>>);
          <<"result">> -> openagentic_case_store_common_lookup:get_bin(Event, [final_text], <<>>);
          <<"assistant.message">> -> openagentic_case_store_common_lookup:get_bin(Event, [text], <<>>);
          _ -> <<>>
        end,
      case byte_size(openagentic_case_store_common_core:trim_bin(Candidate)) > 0 of
        true -> Candidate;
        false -> Best0
      end
    end,
    <<>>,
    Events
  ).

infer_candidate_specs_from_text(Text0, DefaultTimezone) ->
  Text = openagentic_case_store_common_core:normalize_newlines(openagentic_case_store_common_core:to_bin(Text0)),
  Lines0 = binary:split(Text, <<"\n">>, [global]),
  Lines = [openagentic_case_store_common_core:trim_bin(Line) || Line <- Lines0, byte_size(openagentic_case_store_common_core:trim_bin(Line)) > 0],
  BulletLines0 = [openagentic_case_store_common_core:strip_bullet(Line) || Line <- Lines, openagentic_case_store_common_core:is_bullet_line(Line)],
  BulletLines =
    case [Line || Line <- BulletLines0, candidate_like_line(Line)] of
      [] -> BulletLines0;
      Filtered -> Filtered
    end,
  [candidate_spec_from_line(Line, DefaultTimezone) || Line <- BulletLines, byte_size(Line) > 0].

candidate_like_line(Line0) ->
  Line = string:lowercase(openagentic_case_store_common_core:to_bin(Line0)),
  lists:any(
    fun (Pattern) -> binary:match(Line, Pattern) =/= nomatch end,
    [<<"监测">>, <<"跟踪">>, <<"观察">>, <<"关注">>, <<"monitor">>, <<"track">>, <<"watch">>]
  ).

candidate_spec_from_line(Line0, DefaultTimezone) ->
  Line = openagentic_case_store_common_core:trim_bin(Line0),
  #{
    title => shorten_title(Line),
    mission_statement => Line,
    objective => Line,
    default_timezone => DefaultTimezone,
    schedule_policy => openagentic_case_store_case_support:default_schedule_policy(DefaultTimezone),
    report_contract => openagentic_case_store_case_support:default_report_contract(),
    alert_rules => #{},
    source_strategy => #{},
    tool_profile => #{},
    credential_requirements => #{},
    autonomy_policy => #{mode => <<"review_required">>},
    promotion_policy => #{},
    extracted_summary => Line
  }.

shorten_title(Line) ->
  case byte_size(Line) =< 48 of
    true -> Line;
    false -> binary:part(Line, 0, 48)
  end.
