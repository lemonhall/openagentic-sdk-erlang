-module(openagentic_hook_engine).

-export([run_pre_tool_use/4, run_post_tool_use/4]).

run_pre_tool_use(Engine0, ToolName0, ToolInput0, Context0) ->
  Engine = ensure_map(Engine0),
  ToolName = to_bin(ToolName0),
  ToolInput = ensure_map(ToolInput0),
  Context = ensure_map(Context0),
  Matchers = ensure_list(maps:get(pre_tool_use, Engine, maps:get(preToolUse, Engine, []))),
  run_matchers(<<"PreToolUse">>, Matchers, ToolName, ToolInput, Context, pre).

run_post_tool_use(Engine0, ToolName0, ToolOutput0, Context0) ->
  Engine = ensure_map(Engine0),
  ToolName = to_bin(ToolName0),
  ToolOutput =
    case ToolOutput0 of
      undefined -> null;
      V -> V
    end,
  Context = ensure_map(Context0),
  Matchers = ensure_list(maps:get(post_tool_use, Engine, maps:get(postToolUse, Engine, []))),
  run_matchers(<<"PostToolUse">>, Matchers, ToolName, ToolOutput, Context, post).

run_matchers(HookPoint, Matchers, ToolName, Current0, Context, Kind) ->
  run_matchers_loop(HookPoint, Matchers, ToolName, Current0, Context, Kind, [], undefined).

run_matchers_loop(_HookPoint, [], _ToolName, Current, _Context, pre, EvAccRev, Decision) ->
  #{input => ensure_map(Current), events => lists:reverse(EvAccRev), decision => Decision};
run_matchers_loop(_HookPoint, [], _ToolName, Current, _Context, post, EvAccRev, Decision) ->
  #{output => Current, events => lists:reverse(EvAccRev), decision => Decision};
run_matchers_loop(HookPoint, [M0 | Rest], ToolName, Current0, Context, Kind, EvAccRev, Decision0) ->
  M = ensure_map(M0),
  Name = to_bin(maps:get(name, M, <<>>)),
  Pattern = to_bin(maps:get(tool_name_pattern, M, maps:get(toolNamePattern, M, <<"*">>))),
  Matched = match_name(Pattern, ToolName),
  Start = erlang:monotonic_time(microsecond),
  {Current1, Decision1, Action} =
    case Matched of
      false ->
        {Current0, Decision0, undefined};
      true ->
        apply_matcher(M, Kind, Current0, Context)
    end,
  End = erlang:monotonic_time(microsecond),
  DurationMs = (End - Start) / 1000.0,
  Ev = openagentic_events:hook_event(HookPoint, Name, Matched, DurationMs, Action, undefined, undefined),
  case Decision1 of
    D2 when is_map(D2) ->
      case maps:get(block, D2, false) of
        true ->
          run_matchers_loop(HookPoint, [], ToolName, Current1, Context, Kind, [Ev | EvAccRev], D2);
        false ->
          run_matchers_loop(HookPoint, Rest, ToolName, Current1, Context, Kind, [Ev | EvAccRev], Decision1)
      end;
    _ ->
      run_matchers_loop(HookPoint, Rest, ToolName, Current1, Context, Kind, [Ev | EvAccRev], Decision1)
  end.

apply_matcher(M, pre, Current0, _Context) ->
  Block = bool_true(maps:get(block, M, false)) orelse to_bin(maps:get(action, M, <<>>)) =:= <<"block">>,
  case Block of
    true ->
      Reason = to_bin(maps:get(block_reason, M, maps:get(blockReason, M, <<"blocked by hook">>))),
      {Current0, #{block => true, block_reason => Reason}, <<"block">>};
    false ->
      Override = maps:get(override_input, M, maps:get(overrideInput, M, undefined)),
      case Override of
        V when is_map(V) ->
          {V, undefined, to_bin(maps:get(action, M, <<"rewrite">>))};
        _ ->
          {Current0, undefined, to_bin(maps:get(action, M, undefined))}
      end
  end;
apply_matcher(M, post, Current0, _Context) ->
  Block = bool_true(maps:get(block, M, false)) orelse to_bin(maps:get(action, M, <<>>)) =:= <<"block">>,
  case Block of
    true ->
      Reason = to_bin(maps:get(block_reason, M, maps:get(blockReason, M, <<"blocked by hook">>))),
      {Current0, #{block => true, block_reason => Reason}, <<"block">>};
    false ->
      Override = maps:get(override_output, M, maps:get(overrideToolOutput, M, undefined)),
      case Override of
        undefined ->
          {Current0, undefined, to_bin(maps:get(action, M, undefined))};
        _ ->
          {Override, undefined, to_bin(maps:get(action, M, <<"rewrite">>))}
      end
  end.

match_name(Pattern0, Name0) ->
  Pattern = ensure_list(Pattern0),
  Name = ensure_list(Name0),
  Segs = string:split(Pattern, "|", all),
  lists:any(
    fun (S0) ->
      S = string:trim(S0),
      case S of
        "" -> false;
        _ -> wildcard_match(S, Name)
      end
    end,
    Segs
  ).

wildcard_match(Pattern0, Text0) ->
  Pattern = ensure_list(Pattern0),
  Text = ensure_list(Text0),
  %% Kotlin-equivalent wildcard: '*' => '.*', '?' => '.', rest escaped
  ReBody = lists:flatten([wc_piece(C) || C <- Pattern]),
  Re = iolist_to_binary(["^", ReBody, "$"]),
  case re:run(Text, Re, [{capture, none}]) of
    match -> true;
    nomatch -> false
  end.

wc_piece($*) -> ".*";
wc_piece($?) -> ".";
wc_piece($\\) -> "\\\\";
wc_piece($.) -> "\\.";
wc_piece($+) -> "\\+";
wc_piece($() -> "\\(";
wc_piece($)) -> "\\)";
wc_piece($[) -> "\\[";
wc_piece($]) -> "\\]";
wc_piece(${) -> "\\{";
wc_piece($}) -> "\\}";
wc_piece($^) -> "\\^";
wc_piece($$) -> "\\$";
wc_piece($|) -> "\\|";
wc_piece(C) -> [C].

bool_true(true) -> true;
bool_true(false) -> false;
bool_true(B) when is_binary(B) ->
  case string:lowercase(string:trim(B)) of
    <<"true">> -> true;
    <<"1">> -> true;
    <<"yes">> -> true;
    <<"y">> -> true;
    _ -> false
  end;
bool_true(L) when is_list(L) ->
  bool_true(unicode:characters_to_binary(L, utf8));
bool_true(_) ->
  false.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

ensure_list(B) when is_binary(B) -> binary_to_list(B);
ensure_list(L) when is_list(L) -> L;
ensure_list(A) when is_atom(A) -> atom_to_list(A);
ensure_list(I) when is_integer(I) -> integer_to_list(I);
ensure_list(Other) -> lists:flatten(io_lib:format("~p", [Other])).

to_bin(undefined) -> <<>>;
to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L, utf8);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other]), utf8).
