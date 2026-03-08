-module(openagentic_permissions_finalize).

-export([finalize_prompt/3]).

finalize_prompt(ToolName0, Question0, Answer0) ->
  ToolName = openagentic_permissions_utils:to_bin(ToolName0),
  Question = openagentic_permissions_utils:ensure_map(Question0),
  AnswerTxt = openagentic_permissions_utils:truncate_bin(
    string:trim(openagentic_permissions_utils:to_bin(Answer0)),
    240
  ),
  Allowed = openagentic_permissions_utils:parse_allowed(Answer0),
  #{
    allowed => Allowed,
    question => Question,
    deny_message => deny_message(ToolName, AnswerTxt, Allowed)
  }.

deny_message(_ToolName, _AnswerTxt, true) ->
  undefined;
deny_message(ToolName, AnswerTxt, false) ->
  case byte_size(AnswerTxt) > 0 of
    true -> <<"PermissionGate: user answered '", AnswerTxt/binary, "'; denied tool '", ToolName/binary, "'">>;
    false -> <<"PermissionGate: user denied tool '", ToolName/binary, "'">>
  end.
