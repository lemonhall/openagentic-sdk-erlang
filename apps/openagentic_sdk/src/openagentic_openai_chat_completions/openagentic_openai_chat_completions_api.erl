-module(openagentic_openai_chat_completions_api).

-export([complete/1]).

-define(DEFAULT_BASE_URL, "https://api.openai.com/v1").
-define(DEFAULT_TIMEOUT_MS, 60000).

complete(Req0) ->
  Req = openagentic_openai_chat_completions_utils:ensure_map(Req0),
  case {
    openagentic_openai_chat_completions_utils:get_req(api_key, Req),
    openagentic_openai_chat_completions_utils:get_req(model, Req)
  } of
    {{ok, ApiKey0}, {ok, Model0}} ->
      ApiKey = openagentic_openai_chat_completions_utils:to_list(ApiKey0),
      Model = openagentic_openai_chat_completions_utils:to_bin(Model0),
      BaseUrl = openagentic_openai_chat_completions_utils:to_list(maps:get(base_url, Req, ?DEFAULT_BASE_URL)),
      TimeoutMs = maps:get(timeout_ms, Req, ?DEFAULT_TIMEOUT_MS),
      InputItems = openagentic_openai_chat_completions_utils:ensure_list(maps:get(input, Req, [])),
      Tools0 = openagentic_openai_chat_completions_utils:ensure_list(maps:get(tools, Req, [])),
      Messages = openagentic_openai_chat_completions_transform:responses_input_to_chat_messages(InputItems),
      Tools = openagentic_openai_chat_completions_transform:responses_tools_to_chat_tools(Tools0),
      openagentic_openai_chat_completions_runtime:do_complete(ApiKey, BaseUrl, Model, TimeoutMs, Messages, Tools);
    {ApiKeyRes, ModelRes} ->
      {error, {missing_required, [ApiKeyRes, ModelRes]}}
  end.
