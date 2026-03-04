• 可以的，这个仓库里已经有 CLI 入口模块：apps/openagentic_sdk/src/openagentic_cli.erl，它会按“flags > 项目目录 .env > 系统环境变量”的顺序取 OPENAI_API_KEY 和 OPENAI_MODEL/MODEL。

  在 PowerShell 里这样启动（推荐先用交互 chat 验证）：

  cd E:\development\openagentic-sdk-erlang
  . .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify   # 不需要代理就去掉 -EnableProxy
  rebar3 shell

  进入 Erlang shell 后执行：

  openagentic_cli:main(["chat"]).

  - 退出：在提示符里输入 /exit
  - 如果你要指定 .env 所在目录：openagentic_cli:main(["chat","--project-dir","E:/development/openagentic-sdk-erlang"]).（用正斜杠省去转义）
  - 非交互跑一条：openagentic_cli:main(["run","你好，介绍下你自己"] ).

  会话落盘位置（脚本已设到 E 盘）：E:\openagentic-sdk\sessions\<session_id>\meta.json 和 events.jsonl。

  按 apn-pushtool 的安全规则，真实推送需要你明确确认一次：你要我现在发一条到你手机吗（标题 openagentic-sdk-erlang，正文 启动指引完成）？