-module(openagentic_permissions).

-export([
  bypass/0,
  deny/0,
  prompt/0,
  prompt/1,
  default/1,
  approve/4
]).

-type permission_mode() :: bypass | deny | prompt | default.

%% Gate is a map to keep config extensible.
-type gate() :: #{
  mode := permission_mode(),
  user_answerer => fun((map()) -> any())
}.

-spec bypass() -> gate().
bypass() ->
  #{mode => bypass}.

-spec deny() -> gate().
deny() ->
  #{mode => deny}.

-spec prompt() -> gate().
prompt() ->
  #{mode => prompt}.

-spec prompt(any()) -> gate().
prompt(UserAnswerer) ->
  Gate = #{mode => prompt},
  case UserAnswerer of
    F when is_function(F, 1) -> Gate#{user_answerer => F};
    _ -> Gate
  end.

-spec default(any()) -> gate().
default(UserAnswererOrUndefined) ->
  Gate = #{mode => default},
  case UserAnswererOrUndefined of
    F when is_function(F, 1) -> Gate#{user_answerer => F};
    _ -> Gate
  end.

%% Approve tool execution.
%%
%% Returns ApprovalResult map (Kotlin-aligned shape):
%% - allowed: boolean()
%% - question: map() | undefined
%% - updated_input: map() | undefined
%% - deny_message: binary() | undefined
-spec approve(gate(), any(), any(), any()) -> map().
approve(Gate0, ToolName0, ToolInput0, Context0) ->
  Gate = ensure_map(Gate0),
  ToolName = to_bin(ToolName0),
  ToolInput = ensure_map(ToolInput0),
  Context = ensure_map(Context0),

  %% Always allow asking the user.
  case ToolName of
    <<"AskUserQuestion">> ->
      #{allowed => true};
    _ ->
      Mode = maps:get(mode, Gate, default),
      approve_mode(Mode, Gate, ToolName, ToolInput, Context)
  end.

approve_mode(bypass, _Gate, _ToolName, _ToolInput, _Context) ->
  #{allowed => true};
approve_mode(deny, _Gate, ToolName, _ToolInput, _Context) ->
  #{allowed => false, deny_message => <<"PermissionGate(mode=DENY) denied tool '", ToolName/binary, "'">>};
approve_mode(default, Gate, ToolName, ToolInput, Context) ->
  Safe = safe_tools(),
  case lists:member(ToolName, Safe) of
    true ->
      case safe_schema_ok(ToolName, ToolInput) of
        true -> #{allowed => true};
        false ->
          #{
            allowed => false,
            deny_message => <<"PermissionGate(mode=DEFAULT) schema parse failed for tool '", ToolName/binary, "'">>
          }
      end;
    false ->
      %% fallthrough to prompt behavior
      approve_mode(prompt, Gate, ToolName, ToolInput, Context)
  end;
approve_mode(prompt, Gate, ToolName, _ToolInput, Context) ->
  Qid = question_id(Context),
  Question = #{
    type => <<"user.question">>,
    question_id => Qid,
    prompt => <<"Allow tool ", ToolName/binary, "?">>,
    choices => [<<"yes">>, <<"no">>]
  },
  case maps:get(user_answerer, Gate, undefined) of
    F when is_function(F, 1) ->
      Answer = F(Question),
      AnswerTxt = truncate_bin(string:trim(to_bin(Answer)), 240),
      Allowed = parse_allowed(Answer),
      #{
        allowed => Allowed,
        question => Question,
        deny_message =>
          case Allowed of
            true ->
              undefined;
            false ->
              case byte_size(AnswerTxt) > 0 of
                true -> <<"PermissionGate: user answered '", AnswerTxt/binary, "'; denied tool '", ToolName/binary, "'">>;
                false -> <<"PermissionGate: user denied tool '", ToolName/binary, "'">>
              end
          end
      };
    _ ->
      ModeUpper = mode_upper(maps:get(mode, Gate, prompt)),
      #{
        allowed => false,
        deny_message =>
          <<"PermissionGate(mode=", ModeUpper/binary, ") requires userAnswerer, but none is configured for tool '", ToolName/binary, "'">>
      }
  end.

safe_tools() ->
  [
    <<"List">>,
    <<"Read">>,
    <<"Glob">>,
    <<"Grep">>,
    <<"WebFetch">>,
    <<"WebSearch">>,
    <<"Skill">>,
    <<"SlashCommand">>,
    <<"AskUserQuestion">>
  ].

safe_schema_ok(<<"Read">>, Input) ->
  non_empty_string_any(Input, [<<"file_path">>, <<"filePath">>, file_path, filePath]);
safe_schema_ok(<<"List">>, Input) ->
  non_empty_string_any(Input, [<<"path">>, path, <<"dir">>, dir, <<"directory">>, directory]);
safe_schema_ok(<<"Glob">>, Input) ->
  non_empty_string_any(Input, [<<"pattern">>, pattern]);
safe_schema_ok(<<"Grep">>, Input) ->
  non_empty_string_any(Input, [<<"query">>, query]);
safe_schema_ok(<<"WebFetch">>, Input) ->
  non_empty_string_any(Input, [<<"url">>, url]);
safe_schema_ok(<<"WebSearch">>, Input) ->
  non_empty_string_any(Input, [<<"query">>, query, <<"q">>, q]);
safe_schema_ok(_, _Input) ->
  true.

non_empty_string_any(Map, Keys) ->
  lists:any(
    fun (K) ->
      case maps:get(K, Map, undefined) of
        undefined -> false;
        V ->
          Bin = to_bin(V),
          byte_size(string:trim(Bin)) > 0
      end
    end,
    Keys
  ).

mode_upper(bypass) -> <<"BYPASS">>;
mode_upper(deny) -> <<"DENY">>;
mode_upper(prompt) -> <<"PROMPT">>;
mode_upper(default) -> <<"DEFAULT">>;
mode_upper(A) when is_atom(A) -> mode_upper(prompt);
mode_upper(_) -> <<"PROMPT">>.

question_id(Context) ->
  case maps:get(tool_use_id, Context, maps:get(<<"tool_use_id">>, Context, undefined)) of
    undefined -> random_hex(8);
    V ->
      Bin = to_bin(V),
      case byte_size(Bin) of
        0 -> random_hex(8);
        _ -> Bin
      end
  end.

parse_allowed(Answer0) ->
  case Answer0 of
    true -> true;
    false -> false;
    1 -> true;
    0 -> false;
    _ ->
      S = string:lowercase(string:trim(to_bin(Answer0))),
      lists:member(S, [<<"y">>, <<"yes">>, <<"true">>, <<"1">>, <<"allow">>, <<"ok">>])
  end.

random_hex(NBytes) ->
  Bytes = crypto:strong_rand_bytes(NBytes),
  iolist_to_binary([io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Bytes]).

truncate_bin(Bin0, Max) when is_integer(Max), Max > 0 ->
  Bin = to_bin(Bin0),
  case byte_size(Bin) > Max of
    true -> <<(binary:part(Bin, 0, Max))/binary, "...">>;
    false -> Bin
  end.

ensure_map(M) when is_map(M) -> M;
ensure_map(L) when is_list(L) -> maps:from_list(L);
ensure_map(_) -> #{}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> iolist_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(I) when is_integer(I) -> iolist_to_binary(integer_to_list(I));
to_bin(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
