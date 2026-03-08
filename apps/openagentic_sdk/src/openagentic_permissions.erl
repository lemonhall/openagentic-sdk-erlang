-module(openagentic_permissions).

-export([
  bypass/0,
  deny/0,
  prompt/0,
  prompt/1,
  default/1,
  approve/4,
  finalize_prompt/3
]).

-type permission_mode() :: bypass | deny | prompt | default.
-type gate() :: #{
  mode := permission_mode(),
  user_answerer => fun((map()) -> any())
}.

-spec bypass() -> gate().
bypass() ->
  openagentic_permissions_gate:bypass().

-spec deny() -> gate().
deny() ->
  openagentic_permissions_gate:deny().

-spec prompt() -> gate().
prompt() ->
  openagentic_permissions_gate:prompt().

-spec prompt(any()) -> gate().
prompt(UserAnswerer) ->
  openagentic_permissions_gate:prompt(UserAnswerer).

-spec default(any()) -> gate().
default(UserAnswererOrUndefined) ->
  openagentic_permissions_gate:default(UserAnswererOrUndefined).

-spec approve(gate(), any(), any(), any()) -> map().
approve(Gate, ToolName, ToolInput, Context) ->
  openagentic_permissions_approve:approve(Gate, ToolName, ToolInput, Context).

-spec finalize_prompt(any(), map(), any()) -> map().
finalize_prompt(ToolName, Question, Answer) ->
  openagentic_permissions_finalize:finalize_prompt(ToolName, Question, Answer).
