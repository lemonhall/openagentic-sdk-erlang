-module(openagentic_tool_edit_anchors).

-export([anchors_ok/4]).

anchors_ok(_Text, _IdxOld, undefined, undefined) ->
  ok;
anchors_ok(Text, IdxOld, Before0, After0) ->
  Before = case Before0 of undefined -> undefined; BeforeVal -> openagentic_tool_edit_utils:to_bin(BeforeVal) end,
  After = case After0 of undefined -> undefined; AfterVal -> openagentic_tool_edit_utils:to_bin(AfterVal) end,
  IdxBefore = case Before of undefined -> -1; _ -> match_idx(Text, Before) end,
  IdxAfter = case After of undefined -> -1; _ -> match_idx(Text, After) end,
  case Before of
    undefined -> after_ok(IdxOld, After, IdxAfter);
    _ when IdxBefore < 0 -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'before' anchor not found in file">>}};
    _ when IdxBefore >= IdxOld -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'before' must appear before 'old'">>}};
    _ -> after_ok(IdxOld, After, IdxAfter)
  end.

after_ok(_IdxOld, undefined, _IdxAfter) -> ok;
after_ok(_IdxOld, _After, IdxAfter) when IdxAfter < 0 -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'after' anchor not found in file">>}};
after_ok(IdxOld, _After, IdxAfter) when IdxOld >= IdxAfter -> {error, {kotlin_error, <<"IllegalArgumentException">>, <<"Edit: 'after' must appear after 'old'">>}};
after_ok(_IdxOld, _After, _IdxAfter) -> ok.

match_idx(Text, Needle) ->
  case binary:match(Text, Needle) of
    nomatch -> -1;
    {I, _} -> I
  end.
