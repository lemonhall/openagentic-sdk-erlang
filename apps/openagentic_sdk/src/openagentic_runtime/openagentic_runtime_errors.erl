-module(openagentic_runtime_errors).
-export([error_phase/1,error_type/1,provider_error_type/1,session_error_type/1,is_provider_error/1,error_message/2,provider_label/1,provider_url/1,trim_trailing_slash/1,missing_required_keys/1]).

error_phase(Reason) ->
  case is_provider_error(Reason) of
    true -> <<"provider">>;
    false -> <<"session">>
  end.

error_type(Reason) ->
  case is_provider_error(Reason) of
    true -> provider_error_type(Reason);
    false -> session_error_type(Reason)
  end.

provider_error_type({http_error, 429, _Headers, _Body}) -> <<"ProviderRateLimitException">>;
provider_error_type({http_error, Status, _Headers, _Body}) when is_integer(Status) -> <<"ProviderHttpException">>;
provider_error_type(timeout) -> <<"ProviderTimeoutException">>;
provider_error_type({http_stream_error, _}) -> <<"ProviderTimeoutException">>;
provider_error_type({httpc_request_failed, _}) -> <<"ProviderTimeoutException">>;
provider_error_type(stream_ended_without_response_completed) -> <<"ProviderInvalidResponseException">>;
provider_error_type({provider_error, _}) -> <<"ProviderInvalidResponseException">>;
provider_error_type(_) -> <<"ProviderInvalidResponseException">>.

session_error_type({missing_required, _}) -> <<"IllegalArgumentException">>;
session_error_type({invalid_proxy, _}) -> <<"IllegalArgumentException">>;
session_error_type({httpc_set_options_failed, _}) -> <<"IllegalArgumentException">>;
session_error_type(_) -> <<"RuntimeException">>.

is_provider_error({http_error, _Status, _Headers, _Body}) -> true;
is_provider_error({http_stream_error, _}) -> true;
is_provider_error({httpc_request_failed, _}) -> true;
is_provider_error(timeout) -> true;
is_provider_error(stream_ended_without_response_completed) -> true;
is_provider_error({provider_error, _}) -> true;
is_provider_error(_) -> false.

error_message(State0, Reason0) ->
  Reason = Reason0,
  ProviderMod = maps:get(provider_mod, State0, undefined),
  ProviderLabel = provider_label(ProviderMod),
  Url = provider_url(State0),
  Msg =
    case Reason of
      {http_error, Status, _Headers, Body} when is_integer(Status) ->
        Body2 = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(Body), 2000),
        case Status of
          429 ->
            %% Kotlin parity: ProviderRateLimitException message starts with "HTTP 429 from <url>: ..."
            <<"HTTP 429 from ", Url/binary, ": ", Body2/binary>>;
          _ ->
            iolist_to_binary(["HTTP ", integer_to_list(Status), " from ", Url, ": ", Body2])
        end;
      stream_ended_without_response_completed ->
        %% Kotlin parity: runtime wraps stream failures as ProviderInvalidResponseException.
        <<"provider stream failed: stream ended without response.completed">>;
      {provider_error, ErrObj} ->
        ErrStr = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(ErrObj), 2000),
        <<"provider stream failed: ", ErrStr/binary>>;
      {http_stream_error, R} ->
        R2 = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(R), 2000),
        <<"provider stream error: ", R2/binary>>;
      timeout ->
        <<ProviderLabel/binary, ": timeout">>;
      {httpc_request_failed, R} ->
        R2 = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(R), 2000),
        <<ProviderLabel/binary, ": request failed: ", R2/binary>>;
      {missing_required, Missing} ->
        %% Kotlin parity: providers use require(...) which throws IllegalArgumentException with "XxxProvider: apiKey is required".
        MissingKeys = missing_required_keys(Missing),
        case lists:member(api_key, MissingKeys) of
          true -> <<ProviderLabel/binary, ": apiKey is required">>;
          false ->
            case lists:member(model, MissingKeys) of
              true -> <<ProviderLabel/binary, ": model is required">>;
              false -> openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(Reason), 2000)
            end
        end;
      {invalid_proxy, R} ->
        R2 = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(R), 2000),
        <<"invalid proxy: ", R2/binary>>;
      {httpc_set_options_failed, R} ->
        R2 = openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(R), 2000),
        <<"httpc set_options failed: ", R2/binary>>;
      _ ->
        openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(Reason), 2000)
    end,
  openagentic_runtime_truncate_hint:truncate_bin(openagentic_runtime_utils:to_bin(Msg), 2000).

provider_label(openagentic_openai_responses) -> <<"OpenAIResponsesHttpProvider">>;
provider_label(openagentic_openai_chat_completions) -> <<"OpenAIChatCompletionsHttpProvider">>;
provider_label(Other) -> openagentic_runtime_utils:to_bin(Other).

provider_url(State0) ->
  Base0 = string:trim(openagentic_runtime_utils:to_bin(maps:get(base_url, State0, <<"">>))),
  Base1 = trim_trailing_slash(Base0),
  ProviderMod = maps:get(provider_mod, State0, undefined),
  case ProviderMod of
    openagentic_openai_chat_completions -> <<Base1/binary, "/chat/completions">>;
    openagentic_openai_responses -> <<Base1/binary, "/responses">>;
    _ -> Base1
  end.

trim_trailing_slash(Bin) when is_binary(Bin) ->
  Sz = byte_size(Bin),
  case Sz of
    0 -> Bin;
    _ ->
      case binary:at(Bin, Sz - 1) of
        $/ -> trim_trailing_slash(binary:part(Bin, 0, Sz - 1));
        _ -> Bin
      end
  end;
trim_trailing_slash(Other) ->
  trim_trailing_slash(openagentic_runtime_utils:to_bin(Other)).

missing_required_keys(Missing0) ->
  Missing = openagentic_runtime_utils:ensure_list(Missing0),
  lists:filtermap(
    fun (One) ->
      case One of
        {error, {missing, K}} -> {true, K};
        {error, {missing, K, _}} -> {true, K};
        {missing, K} -> {true, K};
        K when is_atom(K) -> {true, K};
        _ -> false
      end
    end,
    Missing
  ).
