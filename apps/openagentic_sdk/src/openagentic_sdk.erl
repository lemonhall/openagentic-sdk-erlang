-module(openagentic_sdk).

-export([query/2]).

%% Public facade.
%% For now, we only support OpenAI Responses (SSE streaming) as the network provider.
%%
%% Opts (map):
%% - provider: openai_responses (default)
%% - api_key: string() | binary()
%% - model: string() | binary()
%% - base_url: string() | binary() (default: "https://api.openai.com/v1")
%% - timeout_ms: non_neg_integer() (default: 60000)
query(Prompt, Opts0) ->
  Opts = ensure_map(Opts0),
  Provider = maps:get(provider, Opts, openai_responses),
  case Provider of
    openai_responses ->
      openagentic_runtime:query(Prompt, Opts);
    _ ->
      {error, {unsupported_provider, Provider}}
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.
