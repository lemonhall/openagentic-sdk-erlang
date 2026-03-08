-module(openagentic_cli).
-export([main/1]).
-ifdef(TEST).
-export([
  parse_flags_for_test/1,
  runtime_opts_for_test/1,
  resolve_project_dir_for_test/1,
  tool_use_summary_for_test/2,
  tool_result_lines_for_test/2,
  redact_secrets_for_test/1
]).
-endif.
main(Args) ->
  openagentic_cli_main_dispatch:main(Args).
-ifdef(TEST).
parse_flags_for_test(Args0) ->
  openagentic_cli_flags:parse_flags(openagentic_cli_values:ensure_list(Args0), #{}).
runtime_opts_for_test(Flags0) ->
  openagentic_cli_runtime_opts:runtime_opts(openagentic_cli_values:ensure_map(Flags0)).
resolve_project_dir_for_test(Cwd0) ->
  openagentic_cli_project:resolve_project_dir(openagentic_cli_values:to_list(string:trim(openagentic_cli_values:to_bin(Cwd0)))).
tool_use_summary_for_test(Name0, Input0) ->
  openagentic_cli_tool_use:tool_use_summary(openagentic_cli_values:to_bin(Name0), openagentic_cli_values:ensure_map(Input0)).
tool_result_lines_for_test(Name0, Output0) ->
  openagentic_cli_tool_result:tool_result_lines(openagentic_cli_values:to_bin(Name0), Output0).
redact_secrets_for_test(Bin0) ->
  openagentic_cli_tool_output_utils:redact_secrets(openagentic_cli_values:to_bin(Bin0)).
-endif.
