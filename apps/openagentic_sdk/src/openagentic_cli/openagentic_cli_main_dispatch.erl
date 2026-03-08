-module(openagentic_cli_main_dispatch).
-export([main/1]).
main(Args0) ->
  Args = openagentic_cli_values:ensure_list(Args0),
  case Args of
    ["run" | Rest] -> openagentic_cli_run_chat:run_cmd(Rest);
    ["chat" | Rest] -> openagentic_cli_run_chat:chat_cmd(Rest);
    ["workflow" | Rest] -> openagentic_cli_workflow_web:workflow_cmd(Rest);
    ["web" | Rest] -> openagentic_cli_workflow_web:web_cmd(Rest);
    ["-h"] -> openagentic_cli_main:usage();
    ["--help"] -> openagentic_cli_main:usage();
    _ -> openagentic_cli_main:usage()
  end.
