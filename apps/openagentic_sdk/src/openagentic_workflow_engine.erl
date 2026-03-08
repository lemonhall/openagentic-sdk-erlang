-module(openagentic_workflow_engine).
-export([run/4, start/4, continue/4, continue_start/4]).
-ifdef(TEST).
-export([wait_for_fanout_for_test/3]).
-endif.
run(ProjectDir, WorkflowRelPath, ControllerInput, Opts) ->
  openagentic_workflow_engine_run:run(ProjectDir, WorkflowRelPath, ControllerInput, Opts).
start(ProjectDir, WorkflowRelPath, ControllerInput, Opts) ->
  openagentic_workflow_engine_run:start(ProjectDir, WorkflowRelPath, ControllerInput, Opts).
continue(SessionRoot, WorkflowSessionId, Message, Opts) ->
  openagentic_workflow_engine_continue:continue(SessionRoot, WorkflowSessionId, Message, Opts).
continue_start(SessionRoot, WorkflowSessionId, Message, Opts) ->
  openagentic_workflow_engine_continue:continue_start(SessionRoot, WorkflowSessionId, Message, Opts).
wait_for_fanout_for_test(Pending, Results, State) ->
  openagentic_workflow_engine_fanout_wait:wait_for_fanout_for_test(Pending, Results, State).
