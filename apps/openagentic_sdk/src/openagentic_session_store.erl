-module(openagentic_session_store).

-export([append_event/3, create_session/2, read_events/2, session_dir/2]).

create_session(RootDir0, Metadata) -> openagentic_session_store_append:create_session(RootDir0, Metadata).
append_event(RootDir0, SessionId0, Event0) -> openagentic_session_store_append:append_event(RootDir0, SessionId0, Event0).
read_events(RootDir0, SessionId0) -> openagentic_session_store_read:read_events(RootDir0, SessionId0).
session_dir(RootDir0, SessionId0) -> openagentic_session_store_layout:session_dir(RootDir0, SessionId0).
