-module(openagentic_provider_protocol).

-export([normalize/1]).

%% Provider protocol normalization (Kotlin parity).
%%
%% Kotlin: ProviderProtocol.RESPONSES | ProviderProtocol.LEGACY
%% Erlang: responses | legacy
normalize(undefined) -> responses;
normalize(null) -> responses;
normalize(responses) -> responses;
normalize(legacy) -> legacy;
normalize(A) when is_atom(A) ->
  normalize(atom_to_binary(A, utf8));
normalize(L) when is_list(L) ->
  normalize(unicode:characters_to_binary(L, utf8));
normalize(B) when is_binary(B) ->
  S = string:lowercase(string:trim(B)),
  case S of
    <<>> -> responses;
    <<"responses">> -> responses;
    <<"response">> -> responses;
    <<"resp">> -> responses;
    <<"r">> -> responses;
    <<"legacy">> -> legacy;
    <<"chat">> -> legacy;
    <<"chatcompletions">> -> legacy;
    <<"chat_completions">> -> legacy;
    <<"chat-completions">> -> legacy;
    <<"completions">> -> legacy;
    <<"c">> -> legacy;
    _ -> responses
  end;
normalize(_) ->
  responses.

