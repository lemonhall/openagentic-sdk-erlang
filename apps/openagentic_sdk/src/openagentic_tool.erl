-module(openagentic_tool).

%% Tool behavior (minimal Kotlin-aligned shape).
%%
%% - name/0: tool name (e.g. <<"Read">>)
%% - description/0: human description
%% - run/2: {ok, ToolOutputMap} | {error, Reason}

-callback name() -> binary().
-callback description() -> binary().
-callback run(map(), map()) -> {ok, map()} | {error, any()}.

