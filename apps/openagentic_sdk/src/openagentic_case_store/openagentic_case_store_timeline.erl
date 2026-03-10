-module(openagentic_case_store_timeline).

-export([
  new_event/6,
  append_event/2,
  append_best_effort/2
]).

new_event(CaseId, EventType, Summary0, RelatedObjectRefs0, OpId, Now) ->
  Summary = openagentic_case_store_common_core:to_bin(Summary0),
  RelatedObjectRefs = openagentic_case_store_common_core:ensure_list(RelatedObjectRefs0),
  openagentic_case_store_common_meta:compact_map(
    #{
      event_id => openagentic_case_store_common_meta:new_id(<<"evt">>),
      event_type => EventType,
      case_id => CaseId,
      created_at => Now,
      severity => <<"normal">>,
      summary => Summary,
      actor => undefined,
      related_object_refs => RelatedObjectRefs,
      op_id => OpId,
      session_id => undefined,
      ext => #{}
    }
  ).

append_event(CaseDir, Event0) ->
  Event = openagentic_case_store_common_core:ensure_map(Event0),
  Path = openagentic_case_store_repo_paths:timeline_file(CaseDir),
  ok = filelib:ensure_dir(filename:join([filename:dirname(Path), "x"])),
  Body = openagentic_json:encode_safe(Event),
  file:write_file(Path, <<Body/binary, "\n">>, [append]).

append_best_effort(CaseDir, Event) ->
  try append_event(CaseDir, Event) of
    ok -> ok
  catch
    _:_ -> ok
  end.
