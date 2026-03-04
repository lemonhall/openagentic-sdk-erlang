-module(openagentic_provider).

%% Provider behavior (minimal for now).
%%
%% complete/1 returns:
%% {ok, #{
%%   assistant_text := binary() | <<>>,
%%   tool_calls := [#{tool_use_id := binary(), name := binary(), arguments := map()}],
%%   response_id := binary() | undefined,
%%   usage := map() | undefined
%% }} | {error, any()}.

-callback complete(map()) -> {ok, map()} | {error, any()}.

