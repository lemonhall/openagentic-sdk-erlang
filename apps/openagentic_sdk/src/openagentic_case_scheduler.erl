-module(openagentic_case_scheduler).
-behaviour(gen_server).
-export([start_link/0, configure/1, run_once/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TICK_MS, 5000).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, #{}, []).

configure(Opts0) ->
  gen_server:call(?SERVER, {configure, openagentic_case_scheduler_utils:ensure_map(Opts0)}, 60000).

run_once(Opts0) ->
  openagentic_case_scheduler_due_scan:scan_once(openagentic_case_scheduler_utils:ensure_map(Opts0)).

init(_InitArg) ->
  _ = erlang:send_after(?DEFAULT_TICK_MS, self(), tick),
  {ok, openagentic_case_scheduler_state_refresh:init_state(?DEFAULT_TICK_MS)}.

handle_call({configure, Opts0}, _From, State0) ->
  {reply, ok, openagentic_case_scheduler_state_refresh:apply_config(Opts0, State0, ?DEFAULT_TICK_MS)};
handle_call(_Msg, _From, State) ->
  {reply, {error, unsupported}, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(tick, State0) ->
  TickMs = openagentic_case_scheduler_state_refresh:tick_ms(State0, ?DEFAULT_TICK_MS),
  _ = erlang:send_after(TickMs, self(), tick),
  case maps:get(enabled, State0, false) of
    true ->
      _ = catch openagentic_case_scheduler_due_scan:scan_once(openagentic_case_scheduler_state_refresh:scan_opts(State0)),
      {noreply, State0};
    false ->
      {noreply, State0}
  end;
handle_info(_Info, State) ->
  {noreply, State}.
