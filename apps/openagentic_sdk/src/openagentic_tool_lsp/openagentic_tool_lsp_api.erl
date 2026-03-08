-module(openagentic_tool_lsp_api).

-export([run/2]).

run(Input0, Ctx0) ->
  Input = openagentic_tool_lsp_utils:ensure_map(Input0),
  Ctx = openagentic_tool_lsp_utils:ensure_map(Ctx0),
  ProjectDir = openagentic_tool_lsp_utils:ensure_list(maps:get(project_dir, Ctx, maps:get(projectDir, Ctx, "."))),

  Op0 = maps:get(<<"operation">>, Input, maps:get(operation, Input, undefined)),
  Op = string:trim(openagentic_tool_lsp_utils:to_bin(Op0)),
  File0 =
    openagentic_tool_lsp_utils:first_non_empty(Input, [
      <<"filePath">>, filePath,
      <<"file_path">>, file_path
    ]),
  Line = openagentic_tool_lsp_utils:int_opt(Input, [<<"line">>, line], 0),
  Character = openagentic_tool_lsp_utils:int_opt(Input, [<<"character">>, character], 0),

  case byte_size(Op) > 0 of
    false -> {error, {invalid_input, <<"lsp: 'operation' must be a non-empty string">>}};
    true ->
      case File0 of
        undefined -> {error, {invalid_input, <<"lsp: 'filePath' must be a non-empty string">>}};
        _ ->
          File = openagentic_tool_lsp_utils:to_bin(File0),
          case {Line >= 1, Character >= 1} of
            {false, _} -> {error, {invalid_input, <<"lsp: 'line' must be an integer >= 1">>}};
            {_, false} -> {error, {invalid_input, <<"lsp: 'character' must be an integer >= 1">>}};
            _ ->
              case openagentic_fs:resolve_tool_path(ProjectDir, File) of
                {error, Reason} -> {error, Reason};
                {ok, FullPath0} ->
                  FullPath = openagentic_tool_lsp_utils:ensure_list(FullPath0),
                  case filelib:is_regular(FullPath) of
                    false -> {error, {invalid_input, iolist_to_binary([<<"File not found: ">>, openagentic_fs:norm_abs_bin(FullPath)])}};
                    true ->
                      case openagentic_tool_lsp_config:load_opencode_config(ProjectDir) of
                        {ok, Cfg} ->
                          case openagentic_tool_lsp_config:parse_lsp_enabled(Cfg) of
                            false -> {error, {runtime_error, <<"lsp: disabled by config">>}};
                            true ->
                              Servers = openagentic_tool_lsp_config:parse_lsp_servers(Cfg),
                              openagentic_tool_lsp_actions:do_lsp(Op, FullPath, Line, Character, ProjectDir, Servers)
                          end;
                        {error, Reason2} ->
                          {error, Reason2}
                      end
                  end
              end
          end
      end
  end.
