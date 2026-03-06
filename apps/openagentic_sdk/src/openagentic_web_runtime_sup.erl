-module(openagentic_web_runtime_sup).

-behaviour(supervisor).

-export([start_link/0, ensure_started/0]).
-export([init/1]).

-define(SERVER, ?MODULE).
-define(KEEPER, openagentic_web_runtime_keeper).

start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

ensure_started() ->
  case whereis(?SERVER) of
    Pid when is_pid(Pid) ->
      {ok, Pid};
    undefined ->
      case whereis(?KEEPER) of
        Keeper when is_pid(Keeper) -> wait_for_supervisor(50);
        undefined -> start_with_keeper()
      end
  end.

start_with_keeper() ->
  Parent = self(),
  Ref = make_ref(),
  {Pid, MRef} =
    spawn_monitor(
      fun () ->
        runtime_keeper(Parent, Ref)
      end
    ),
  receive
    {web_runtime_sup_started, Ref, {ok, SupPid}} ->
      _ = erlang:demonitor(MRef, [flush]),
      {ok, SupPid};
    {web_runtime_sup_started, Ref, {error, {already_started, SupPid}}} ->
      _ = erlang:demonitor(MRef, [flush]),
      {ok, SupPid};
    {web_runtime_sup_started, Ref, Other} ->
      _ = erlang:demonitor(MRef, [flush]),
      Other;
    {'DOWN', MRef, process, Pid, Reason} ->
      receive
        {web_runtime_sup_started, Ref, Res} -> Res
      after 50 ->
        {error, {runtime_sup_start_failed, Reason}}
      end
  after 5000 ->
    _ = erlang:demonitor(MRef, [flush]),
    {error, timeout}
  end.

wait_for_supervisor(0) ->
  case whereis(?SERVER) of
    SupPid when is_pid(SupPid) -> {ok, SupPid};
    undefined -> {error, timeout}
  end;
wait_for_supervisor(AttemptsLeft) ->
  case whereis(?SERVER) of
    SupPid when is_pid(SupPid) -> {ok, SupPid};
    undefined ->
      timer:sleep(100),
      wait_for_supervisor(AttemptsLeft - 1)
  end.

runtime_keeper(Parent, Ref) ->
  _ = catch register(?KEEPER, self()),
  process_flag(trap_exit, true),
  Res =
    case whereis(?SERVER) of
      Existing when is_pid(Existing) -> {ok, Existing};
      undefined -> start_link()
    end,
  Parent ! {web_runtime_sup_started, Ref, Res},
  case Res of
    {ok, SupPid} ->
      keep_runtime(SupPid);
    {error, {already_started, SupPid}} ->
      keep_runtime(SupPid);
    _ ->
      ok
  end.

keep_runtime(SupPid) ->
  receive
    {'EXIT', SupPid, Reason} ->
      exit(Reason)
  end.

init([]) ->
  SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
  Children =
    [
      #{
        id => openagentic_web_q,
        start => {openagentic_web_q, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [openagentic_web_q]
      },
      #{
        id => openagentic_workflow_mgr,
        start => {openagentic_workflow_mgr, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [openagentic_workflow_mgr]
      }
    ],
  {ok, {SupFlags, Children}}.
