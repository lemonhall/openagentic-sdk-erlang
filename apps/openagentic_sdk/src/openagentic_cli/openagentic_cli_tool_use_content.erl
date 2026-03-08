-module(openagentic_cli_tool_use_content).
-export([tool_use_summary/2]).

tool_use_summary(<<"Skill">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Name =
    string:trim(
      openagentic_cli_values:to_bin(
        openagentic_cli_values:first_non_blank([
          maps:get(<<"name">>, Input, undefined),
          maps:get(name, Input, undefined),
          maps:get(<<"skill">>, Input, undefined),
          maps:get(skill, Input, undefined)
        ])
      )
    ),
  case byte_size(Name) > 0 of
    true -> iolist_to_binary([<<" name=">>, openagentic_cli_tool_output_utils:safe_preview(Name, 80)]);
    false -> <<>>
  end;
tool_use_summary(<<"SlashCommand">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Name = string:trim(openagentic_cli_values:to_bin(maps:get(<<"name">>, Input, maps:get(name, Input, <<>>)))),
  Args = openagentic_cli_values:to_bin(maps:get(<<"args">>, Input, maps:get(args, Input, maps:get(<<"arguments">>, Input, maps:get(arguments, Input, <<>>))))),
  N2 = openagentic_cli_tool_output_utils:safe_preview(Name, 80),
  A2 = openagentic_cli_tool_output_utils:safe_preview(string:trim(Args), 160),
  case {byte_size(N2) > 0, byte_size(A2) > 0} of
    {true, true} -> iolist_to_binary([<<" name=">>, N2, <<" args=\"">>, A2, <<"\"">>]);
    {true, false} -> iolist_to_binary([<<" name=">>, N2]);
    _ -> <<>>
  end;
tool_use_summary(<<"Write">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  FilePath = string:trim(openagentic_cli_values:to_bin(openagentic_cli_values:first_non_blank([maps:get(<<"file_path">>, Input, undefined), maps:get(file_path, Input, undefined), maps:get(<<"filePath">>, Input, undefined), maps:get(filePath, Input, undefined)]))),
  Overwrite = maps:get(<<"overwrite">>, Input, maps:get(overwrite, Input, undefined)),
  Content0 = maps:get(<<"content">>, Input, maps:get(content, Input, undefined)),
  Bytes =
    case Content0 of
      B when is_binary(B) -> byte_size(B);
      L when is_list(L) -> byte_size(openagentic_cli_values:to_bin(L));
      _ -> undefined
    end,
  P2 = openagentic_cli_tool_output_utils:safe_preview(FilePath, 160),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(P2) > 0 -> iolist_to_binary([<<" file_path=">>, P2]); true -> <<>> end,
        case Bytes of undefined -> <<>>; _ -> iolist_to_binary([<<" bytes=">>, integer_to_binary(Bytes)]) end,
        case Overwrite of undefined -> <<>>; _ -> iolist_to_binary([<<" overwrite=">>, openagentic_cli_values:to_bin(Overwrite)]) end
      ]
    )
  );
tool_use_summary(<<"Edit">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  FilePath = string:trim(openagentic_cli_values:to_bin(openagentic_cli_values:first_non_blank([maps:get(<<"file_path">>, Input, undefined), maps:get(file_path, Input, undefined), maps:get(<<"filePath">>, Input, undefined), maps:get(filePath, Input, undefined)]))),
  Count = maps:get(<<"count">>, Input, maps:get(count, Input, undefined)),
  ReplaceAll = maps:get(<<"replace_all">>, Input, maps:get(replace_all, Input, maps:get(<<"replaceAll">>, Input, maps:get(replaceAll, Input, undefined)))),
  P2 = openagentic_cli_tool_output_utils:safe_preview(FilePath, 160),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(P2) > 0 -> iolist_to_binary([<<" file_path=">>, P2]); true -> <<>> end,
        case Count of undefined -> <<>>; _ -> iolist_to_binary([<<" count=">>, openagentic_cli_values:to_bin(Count)]) end,
        case ReplaceAll of undefined -> <<>>; _ -> iolist_to_binary([<<" replace_all=">>, openagentic_cli_values:to_bin(ReplaceAll)]) end
      ]
    )
  );
tool_use_summary(<<"Bash">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Cmd0 = string:trim(openagentic_cli_values:to_bin(maps:get(<<"command">>, Input, maps:get(command, Input, <<>>)))),
  Workdir = string:trim(openagentic_cli_values:to_bin(maps:get(<<"workdir">>, Input, maps:get(workdir, Input, <<>>)))),
  Timeout = maps:get(<<"timeout_ms">>, Input, maps:get(timeout_ms, Input, maps:get(<<"timeout">>, Input, maps:get(timeout, Input, undefined)))),
  Cmd = openagentic_cli_tool_output_utils:safe_preview(openagentic_cli_tool_output_utils:redact_secrets(Cmd0), 220),
  Wd = openagentic_cli_tool_output_utils:safe_preview(Workdir, 120),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(Cmd) > 0 -> iolist_to_binary([<<" command=\"">>, Cmd, <<"\"">>]); true -> <<>> end,
        if byte_size(Wd) > 0 -> iolist_to_binary([<<" workdir=">>, Wd]); true -> <<>> end,
        case Timeout of undefined -> <<>>; _ -> iolist_to_binary([<<" timeout=">>, openagentic_cli_values:to_bin(Timeout)]) end
      ]
    )
  );
tool_use_summary(<<"NotebookEdit">>, Input0) ->
  Input = openagentic_cli_values:ensure_map(Input0),
  Nb = string:trim(openagentic_cli_values:to_bin(maps:get(<<"notebook_path">>, Input, maps:get(notebook_path, Input, <<>>)))),
  Mode = string:trim(openagentic_cli_values:to_bin(maps:get(<<"edit_mode">>, Input, maps:get(edit_mode, Input, <<>>)))),
  Cell = string:trim(openagentic_cli_values:to_bin(maps:get(<<"cell_id">>, Input, maps:get(cell_id, Input, <<>>)))),
  N2 = openagentic_cli_tool_output_utils:safe_preview(Nb, 160),
  M2 = openagentic_cli_tool_output_utils:safe_preview(Mode, 40),
  C2 = openagentic_cli_tool_output_utils:safe_preview(Cell, 80),
  iolist_to_binary(
    lists:filter(
      fun (B) -> is_binary(B) andalso byte_size(string:trim(B)) > 0 end,
      [
        if byte_size(N2) > 0 -> iolist_to_binary([<<" notebook_path=">>, N2]); true -> <<>> end,
        if byte_size(M2) > 0 -> iolist_to_binary([<<" edit_mode=">>, M2]); true -> <<>> end,
        if byte_size(C2) > 0 -> iolist_to_binary([<<" cell_id=">>, C2]); true -> <<>> end
      ]
    )
  ).
