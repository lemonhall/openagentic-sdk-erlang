-module(openagentic_cli_flags).
-export([parse_flags/2,set_compaction_opt/3,parse_int/1,clamp_int/3]).

parse_flags([], Acc) ->
  {Acc, []};
parse_flags(["--protocol", V | Rest], Acc) ->
  {P, _} = {openagentic_provider_protocol:normalize(V), V},
  parse_flags(Rest, Acc#{protocol => P});
parse_flags(["--model", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{model => openagentic_cli_values:to_bin(V)});
parse_flags(["--api-key", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{api_key => openagentic_cli_values:to_bin(V)});
parse_flags(["--base-url", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{base_url => openagentic_cli_values:to_bin(V)});
parse_flags(["--api-key-header", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{api_key_header => openagentic_cli_values:to_bin(V)});
parse_flags(["--cwd", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{project_dir => openagentic_cli_values:to_bin(V)});
parse_flags(["--project-dir", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{project_dir => openagentic_cli_values:to_bin(V)});
parse_flags(["--resume", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{resume_session_id => openagentic_cli_values:to_bin(V)});
parse_flags(["--permission", V0 | Rest], Acc) ->
  V = string:lowercase(string:trim(openagentic_cli_values:to_bin(V0))),
  Mode =
    case V of
      <<"bypass">> -> bypass;
      <<"deny">> -> deny;
      <<"prompt">> -> prompt;
      <<"default">> -> default;
      _ -> default
    end,
  parse_flags(Rest, Acc#{permission => Mode});
parse_flags(["--stream" | Rest], Acc) ->
  parse_flags(Rest, Acc#{stream => true});
parse_flags(["--no-stream" | Rest], Acc) ->
  parse_flags(Rest, Acc#{stream => false});
parse_flags(["--color" | Rest], Acc) ->
  parse_flags(Rest, Acc#{color => true});
parse_flags(["--no-color" | Rest], Acc) ->
  parse_flags(Rest, Acc#{color => false});
parse_flags(["--render-markdown" | Rest], Acc) ->
  parse_flags(Rest, Acc#{render_markdown => true});
parse_flags(["--no-render-markdown" | Rest], Acc) ->
  parse_flags(Rest, Acc#{render_markdown => false});
parse_flags(["--openai-store", V0 | Rest], Acc) ->
  V = string:lowercase(string:trim(openagentic_cli_values:to_bin(V0))),
  Bool = V =/= <<"0">> andalso V =/= <<"false">> andalso V =/= <<"no">> andalso V =/= <<"off">>,
  parse_flags(Rest, Acc#{openai_store => Bool});
parse_flags(["--no-openai-store" | Rest], Acc) ->
  parse_flags(Rest, Acc#{openai_store => false});
parse_flags(["--max-steps", V0 | Rest], Acc) ->
  Max0 = parse_int(V0),
  Max =
    case Max0 of
      I when is_integer(I) -> clamp_int(I, 1, 200);
      _ -> 50
    end,
  parse_flags(Rest, Acc#{max_steps => Max});
parse_flags(["--context-limit", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, context_limit, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["--reserved", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, reserved, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["--input-limit", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I >= 0 ->
      parse_flags(Rest, set_compaction_opt(Acc, input_limit, I));
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["--dsl", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{workflow_dsl => openagentic_cli_values:to_bin(V)});
parse_flags(["--workflow", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{workflow_dsl => openagentic_cli_values:to_bin(V)});
parse_flags(["--web-bind", V | Rest], Acc) ->
  parse_flags(Rest, Acc#{web_bind => openagentic_cli_values:to_bin(V)});
parse_flags(["--web-port", V0 | Rest], Acc) ->
  case parse_int(V0) of
    I when is_integer(I), I > 0, I < 65536 ->
      parse_flags(Rest, Acc#{web_port => I});
    _ ->
      parse_flags(Rest, Acc)
  end;
parse_flags(["-h" | _Rest], _Acc) ->
  openagentic_cli_main:usage(),
  halt(0);
parse_flags(["--help" | _Rest], _Acc) ->
  openagentic_cli_main:usage(),
  halt(0);
parse_flags([Arg | Rest], Acc) ->
  {Acc2, Pos} = parse_flags(Rest, Acc),
  {Acc2, [Arg | Pos]}.

set_compaction_opt(Acc0, K, V) ->
  Acc = openagentic_cli_values:ensure_map(Acc0),
  Comp0 = openagentic_cli_values:ensure_map(maps:get(compaction, Acc, #{})),
  Acc#{compaction => Comp0#{K => V}}.

parse_int(V0) ->
  case (catch binary_to_integer(string:trim(openagentic_cli_values:to_bin(V0)))) of
    I when is_integer(I) -> I;
    _ -> undefined
  end.

clamp_int(I, Min, Max) when is_integer(I) ->
  erlang:min(Max, erlang:max(Min, I)).
