-module(openagentic_web_q).

-behaviour(gen_server).

-export([start_link/0, ask/2, answer/2]).
-export([init/1, handle_call/3, handle_cast/2]).

%% A tiny in-memory question broker for web UI HITL.
%%
%% - ask(WorkflowSessionId, QuestionMap) blocks until answer arrives (or times out).
%% - answer(QuestionId, Answer) unblocks the waiter.
%%
%% Note: state is in-memory only; v1 simplicity. If the server restarts,
%% pending questions are lost and the workflow run will fail/timeout.

-define(DEFAULT_TIMEOUT_MS, 10 * 60 * 1000).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, #{}, []).

ask(WorkflowSessionId0, Question0) ->
  WorkflowSessionId = to_bin(WorkflowSessionId0),
  Question = ensure_map(Question0),
  Qid = to_bin(maps:get(question_id, Question, maps:get(<<"question_id">>, Question, <<>>))),
  gen_server:call(?MODULE, {ask, WorkflowSessionId, Qid, Question}, ?DEFAULT_TIMEOUT_MS).

answer(QuestionId0, Answer0) ->
  gen_server:cast(?MODULE, {answer, to_bin(QuestionId0), Answer0}).

init(State0) ->
  State = ensure_map(State0),
  {ok, State}.

handle_call({ask, WorkflowSessionId, Qid, Question}, From, State0) ->
  State1 = ensure_map(State0),
  case maps:find(Qid, State1) of
    {ok, #{answer := Ans}} when Ans =/= undefined ->
      {reply, Ans, State1};
    _ ->
      Item = #{
        workflow_session_id => WorkflowSessionId,
        question => Question,
        from => From,
        answer => undefined
      },
      {noreply, State1#{Qid => Item}}
  end;
handle_call(_Other, _From, State0) ->
  {reply, undefined, ensure_map(State0)}.

handle_cast({answer, Qid, Answer0}, State0) ->
  State = ensure_map(State0),
  Answer = Answer0,
  case maps:find(Qid, State) of
    {ok, #{from := undefined} = Item} ->
      {noreply, State#{Qid => Item#{answer => Answer}}};
    {ok, #{from := From} = Item} ->
      gen_server:reply(From, Answer),
      {noreply, State#{Qid => Item#{answer => Answer, from => undefined}}};
    error ->
      {noreply, State}
  end;
handle_cast(_Other, State0) ->
  {noreply, ensure_map(State0)}.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
