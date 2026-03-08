-module(openagentic_case_store_run_attempt_session).
-export([create_attempt_session/5, append_attempt_start_event/6]).

create_attempt_session(RootDir, CaseId, TaskId, RunId, AttemptId) ->
  {ok, SessionId0} =
    openagentic_session_store:create_session(
      RootDir,
      #{
        kind => <<"monitoring_run_attempt">>,
        case_id => CaseId,
        task_id => TaskId,
        run_id => RunId,
        attempt_id => AttemptId
      }
    ),
  openagentic_case_store_common_core:to_bin(SessionId0).

append_attempt_start_event(RootDir, ExecutionSessionId, CaseId, TaskId, RunId, AttemptId) ->
  _ =
    catch
      openagentic_session_store:append_event(
        RootDir,
        openagentic_case_store_common_core:ensure_list(ExecutionSessionId),
        #{
          type => <<"monitoring.attempt.started">>,
          case_id => CaseId,
          task_id => TaskId,
          run_id => RunId,
          attempt_id => AttemptId
        }
      ),
  ok.
