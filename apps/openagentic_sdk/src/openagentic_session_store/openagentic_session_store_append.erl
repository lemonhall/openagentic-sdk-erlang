-module(openagentic_session_store_append).

-export([append_event/3, create_session/2]).

create_session(RootDir0, Metadata) ->
  RootDir = openagentic_session_store_utils:ensure_list(RootDir0),
  SessionId = openagentic_session_store_layout:new_session_id(),
  Dir = openagentic_session_store_layout:session_dir(RootDir, SessionId),
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  Meta = #{session_id => openagentic_session_store_utils:to_bin(SessionId), created_at => erlang:system_time(second) * 1.0, metadata => openagentic_session_store_utils:ensure_map(Metadata)},
  MetaBin = openagentic_json:encode(openagentic_json:to_json_term(Meta)),
  ok = write_text(filename:join([Dir, "meta.json"]), <<MetaBin/binary, "\n">>),
  {ok, SessionId}.

append_event(RootDir0, SessionId0, Event0) ->
  RootDir = openagentic_session_store_utils:ensure_list(RootDir0),
  SessionId = openagentic_session_store_utils:ensure_list(SessionId0),
  Dir = openagentic_session_store_layout:session_dir(RootDir, SessionId),
  ok = filelib:ensure_dir(filename:join([Dir, "x"])),
  Path = filename:join([Dir, "events.jsonl"]),
  ok = openagentic_session_store_tail_repair:repair_truncated_tail(Path),
  Event1 = openagentic_session_store_utils:with_meta(Event0, openagentic_session_store_read:infer_next_seq(Path) + 1, erlang:system_time(millisecond) / 1000.0),
  Event = openagentic_json:to_json_term(Event1),
  ok = append_text(Path, <<(openagentic_json:encode(Event))/binary, "\n">>),
  {ok, Event}.

write_text(Path, Bin) ->
  file:write_file(Path, Bin).

append_text(Path, Bin) ->
  case file:open(Path, [append, binary]) of
    {ok, Io} -> ok = file:write(Io, Bin), file:close(Io);
    Err -> Err
  end.
