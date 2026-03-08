-module(openagentic_runtime_artifacts).
-export([maybe_externalize_tool_output/4,write_tool_output_artifact/4,build_tool_output_filename/2]).

maybe_externalize_tool_output(ToolUseId0, ToolName0, Output0, State0) ->
  Cfg0 = openagentic_runtime_utils:ensure_map(maps:get(tool_output_artifacts, State0, #{})),
  Enabled = maps:get(enabled, Cfg0, maps:get(<<"enabled">>, Cfg0, true)),
  case Enabled of
    false ->
      Output0;
    _ ->
      case Output0 of
        undefined -> Output0;
        null -> Output0;
        _ ->
          Encoded =
            try
              openagentic_json:encode(Output0)
            catch
              _:_ -> undefined
            end,
          case Encoded of
            undefined ->
              Output0;
            _ ->
              MaxBytes = openagentic_runtime_truncate_headtail:int_default(Cfg0, [max_bytes, <<"max_bytes">>], 51200),
              case byte_size(Encoded) =< MaxBytes of
                true ->
                  Output0;
                false ->
                  DirName = openagentic_runtime_utils:ensure_list(maps:get(dir_name, Cfg0, maps:get(dirName, Cfg0, "tool-output"))),
                  Root = openagentic_runtime_utils:ensure_list(maps:get(root, State0)),
                  Dir = filename:join([Root, DirName]),
                  PreviewMax = openagentic_runtime_truncate_headtail:int_default(Cfg0, [preview_max_chars, <<"preview_max_chars">>], 2500),
                  SessionId = openagentic_runtime_utils:to_bin(maps:get(session_id, State0)),
                  ToolUseId = openagentic_runtime_utils:to_bin(ToolUseId0),
                  ToolName = openagentic_runtime_utils:to_bin(ToolName0),
                  OriginalChars = string:length(openagentic_runtime_truncate_headtail:bin_to_list_safe(Encoded)),
                  Preview = openagentic_runtime_truncate_headtail:head_tail_truncate(Encoded, PreviewMax),
                  ArtifactPath = write_tool_output_artifact(Dir, ToolUseId, ToolName, Encoded),
                  Hint = openagentic_runtime_truncate_hint:build_truncation_hint(ArtifactPath, State0),
                  Wrapper0 = #{
                    '_openagentic_truncated' => true,
                    reason => <<"tool_output_too_large">>,
                    session_id => SessionId,
                    tool_use_id => ToolUseId,
                    tool_name => ToolName,
                    original_chars => OriginalChars,
                    preview => Preview,
                    hint => Hint
                  },
                  case ArtifactPath of
                    undefined -> Wrapper0;
                    _ -> Wrapper0#{artifact_path => openagentic_fs:norm_abs_bin(ArtifactPath)}
                  end
              end
          end
      end
  end.

write_tool_output_artifact(Dir0, ToolUseId0, ToolName0, Encoded) ->
  Dir = openagentic_runtime_utils:ensure_list(Dir0),
  ToolUseId = openagentic_runtime_utils:ensure_list(ToolUseId0),
  ToolName = openagentic_runtime_utils:ensure_list(ToolName0),
  case filelib:ensure_dir(filename:join([Dir, "x"])) of
    ok ->
      FileName = build_tool_output_filename(ToolUseId, ToolName),
      Path = filename:join([Dir, FileName]),
      case file:write_file(Path, Encoded) of
        ok -> Path;
        _ -> undefined
      end;
    _ ->
      undefined
  end.

build_tool_output_filename(ToolUseId0, ToolName0) ->
  Id = openagentic_runtime_truncate_hint:safe_piece(ToolUseId0),
  Name = openagentic_runtime_truncate_hint:safe_piece(ToolName0),
  lists:flatten(["tool_", Id, "_", Name, ".json"]).
