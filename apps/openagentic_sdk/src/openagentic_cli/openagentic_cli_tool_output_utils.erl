-module(openagentic_cli_tool_output_utils).
-export([websearch_result_line/1,safe_preview/2,redact_secrets/1,re_replace/3,truncate_bin/2]).

websearch_result_line(R0) ->
  R = openagentic_cli_values:ensure_map(R0),
  Title0 = maps:get(title, R, maps:get(<<"title">>, R, <<>>)),
  Url0 = maps:get(url, R, maps:get(<<"url">>, R, <<>>)),
  Title = truncate_bin(string:trim(openagentic_cli_values:to_bin(Title0)), 120),
  Url = truncate_bin(string:trim(openagentic_cli_values:to_bin(Url0)), 200),
  case byte_size(Title) > 0 of
    true -> iolist_to_binary([<<"- ">>, Title, <<" (">>, Url, <<")">>]);
    false -> iolist_to_binary([<<"- ">>, Url])
  end.

safe_preview(Bin0, Max) ->
  truncate_bin(redact_secrets(openagentic_cli_values:to_bin(Bin0)), Max).

redact_secrets(Bin0) ->
  Bin = openagentic_cli_values:to_bin(Bin0),
  %% Best-effort redaction for common secret shapes. Keep it conservative.
  B1 = re_replace(Bin, <<"(sk-[A-Za-z0-9]{10,})">>, <<"sk-***">>),
  B2 = re_replace(B1, <<"(?i)bearer\\s+[A-Za-z0-9\\-\\._~\\+\\/]+=*">>, <<"Bearer ***">>),
  B3 = re_replace(B2, <<"(?i)(OPENAI_API_KEY|TAVILY_API_KEY)\\s*[:=]\\s*[^\\s\\\"\\']+">>, <<"$1=***">>),
  B4 = re_replace(B3, <<"(?i)(x-api-key|x_api_key|api_key)\\s*[:=]\\s*[^\\s\\\"\\']+">>, <<"$1=***">>),
  B4.

re_replace(Bin, Pattern, Replace) ->
  try
    re:replace(Bin, Pattern, Replace, [global, {return, binary}])
  catch
    _:_ -> Bin
  end.

%% --- Terminal formatting helpers (best-effort; safe to disable via --no-color / NO_COLOR) ---

truncate_bin(Bin0, Max) when is_integer(Max), Max > 0 ->
  Bin = openagentic_cli_values:to_bin(Bin0),
  case byte_size(Bin) > Max of
    true -> <<(binary:part(Bin, 0, Max))/binary, "...">>;
    false -> Bin
  end.
