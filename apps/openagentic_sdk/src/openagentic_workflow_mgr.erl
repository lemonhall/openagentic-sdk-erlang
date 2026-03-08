-module(openagentic_workflow_mgr).
-behaviour(gen_server).
-export([start_link/0, ensure_started/0]).
-export([start_workflow/4, continue_workflow/4, cancel_workflow/2, status/1, status/2]).
-export([note_progress/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-ifdef(TEST).
-export([idle_timeout_ms_for_test/1]).
-endif.

-define(SERVER, ?MODULE).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, #{}, []).

ensure_started() ->
  case whereis(?SERVER) of
    undefined ->
      case start_link() of
        {ok, _Pid} -> ok;
        {error, {already_started, _}} -> ok;
        Other -> erlang:error({workflow_mgr_start_failed, Other})
      end;
    _ -> ok
  end.

start_workflow(ProjectDir, WorkflowRelPath, Prompt, EngineOpts) -> ensure_started(), gen_server:call(?SERVER, {start_workflow, ProjectDir, WorkflowRelPath, Prompt, EngineOpts}, 60000).
continue_workflow(SessionRoot, WorkflowSessionId, Message, EngineOpts) -> ensure_started(), gen_server:call(?SERVER, {continue_workflow, SessionRoot, WorkflowSessionId, Message, EngineOpts}, 60000).
cancel_workflow(SessionRoot, WorkflowSessionId) -> ensure_started(), gen_server:call(?SERVER, {cancel_workflow, SessionRoot, WorkflowSessionId}, 60000).
status(WorkflowSessionId) -> ensure_started(), gen_server:call(?SERVER, {status, undefined, WorkflowSessionId}, 60000).
status(SessionRoot, WorkflowSessionId) -> ensure_started(), gen_server:call(?SERVER, {status, SessionRoot, WorkflowSessionId}, 60000).
note_progress(WorkflowSessionId0, Event0) -> ensure_started(), gen_server:cast(?SERVER, {note_progress, openagentic_workflow_mgr_utils:to_bin(WorkflowSessionId0), openagentic_workflow_mgr_utils:ensure_map(Event0)}).

init(State0) -> openagentic_workflow_mgr_info:init(State0).
handle_call(Msg, From, State0) -> openagentic_workflow_mgr_calls:handle_call(Msg, From, State0).
handle_cast(Msg, State0) -> openagentic_workflow_mgr_info:handle_cast(Msg, State0).
handle_info(Msg, State0) -> openagentic_workflow_mgr_info:handle_info(Msg, State0).

-ifdef(TEST).
idle_timeout_ms_for_test(EngineOpts) -> openagentic_workflow_mgr_stalls:idle_timeout_ms(EngineOpts).
-endif.
