# openagentic-sdk-erlang（中文说明）

English README: [`README.md`](README.md)

`openagentic-sdk-erlang` 是 `openagentic-sdk-kotlin` 的 Erlang/OTP 平行移植项目，目标是在 BEAM 上提供一套可落地的 Agent runtime：

- OpenAI Responses API provider（优先）+ SSE streaming
- Tool-loop（函数调用）+ 权限门禁（HITL：human-in-the-loop）
- 会话落盘（`meta.json` + `events.jsonl`），方便回溯与调试
- 内置工具（Read/List/Glob/Grep/WebSearch/WebFetch/Skill/SlashCommand/…）
- 本地 CLI 用来做端到端验证（适配 Windows 11 + PowerShell + 代理环境）

> 本文档默认以 Windows 11 + PowerShell 7.x 为主（连续执行命令用 `;`，不要用 `&&`）。

## 当前状态

仓库提供两类验证方式：

- 离线单测（确定性）：`rebar3 eunit`
- 真联网 E2E（真实网络 + 真实 key，可选）：`.\scripts\e2e-online-suite.ps1 -E2E`

## 规范与协议

- 远程 subagent（HTTP + SSE）：`docs/spec/agent-host-protocol.md`
- 中文说明：`docs/spec/agent-host-protocol.zh_ch.md`

## 环境要求

- Erlang/OTP 28（已验证）
- `rebar3`
- PowerShell 7.x 推荐

## 快速开始（Windows PowerShell）

1) 先执行环境脚本，把 Erlang 与缓存目录指到 **E 盘**（可选开启代理）：

```powershell
# 需要代理（大陆网络）：
. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify

# 不需要代理：
# . .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

说明：
- 默认代理地址是 `http://127.0.0.1:7897`（可用 `-Proxy` 覆盖）。
- 脚本会把 rebar3/hex/httpc 的数据目录都放到 E 盘，避免 C 盘爆炸。

2) 跑单测（推荐在“新开终端”里跑一次，确保环境变量已刷新）：

```powershell
rebar3 eunit
```

3) 启动交互式 CLI（通过 Erlang shell）：

```powershell
rebar3 shell
```

进入 Erlang shell 后：

```erlang
openagentic_cli:main(["chat"]).
%% 或：
openagentic_cli:main(["run", "你好，Erlang!"]).
```

## 配置（.env）

CLI 会从项目目录读取 `.env`。
注意：不要把真实 key 粘贴到 issue/log 里，本仓库已把 `.env` 加入 `.gitignore`。

最小 `.env` 示例（别填真实密钥到公共场合）：

```dotenv
OPENAI_API_KEY=your_key_here
MODEL=gpt-4.1-mini
```

常用键：

- `OPENAI_API_KEY`（必填）
- `OPENAI_MODEL` 或 `MODEL`（必填）
- `OPENAI_BASE_URL`（可选；默认 `https://api.openai.com/v1`）
- `OPENAI_API_KEY_HEADER`（可选；默认 `authorization`；某些网关需要 `x-api-key` 等）
- `OPENAI_STORE`（可选；Responses API 默认开启 store）

WebSearch（可选，但想要“真正的搜索能力”建议配上）：

- `TAVILY_API_KEY`（建议）
- `TAVILY_URL`（可选；默认 `https://api.tavily.com`，并会自动补成 `/search`）

## CLI 常用参数

CLI 入口：`openagentic_cli:main/1`

- `--max-steps <1..200>`：每次 query 的最大“模型 step”轮数（默认：`50`）
- `--stream` / `--no-stream`：是否启用流式输出（默认：开）
- `--permission <bypass|deny|prompt|default>`：权限门禁模式（默认：`default`）
- `--color` / `--no-color`：终端 ANSI 颜色（默认：自动）
- `--render-markdown` / `--no-render-markdown`：提升长 Markdown 可读性（仅对非流式输出生效）

颜色也可以通过环境变量关闭：

- `NO_COLOR=1`（标准）
- `OPENAGENTIC_NO_COLOR=1`（项目约定）

## 权限门禁（HITL）

运行时内置 PermissionGate 用来控制工具调用：

- `default` 模式下：**安全的只读工具默认直接放行**，避免频繁 `yes/no` 打断。
- 写文件/执行 shell/跑 task 等“危险工具”：需要用户明确允许。

当某个工具被拒绝时，拒绝原因会以“工具错误输出”的形式回传给模型，避免模型陷入反复重试的死循环。

## 工具（概览）

运行时注册了一套工具供模型使用，例如：

- 文件系统：`List` / `Read` / `Glob` / `Grep` / `Write` / `Edit`
- 网络：`WebSearch`（Tavily 后端）/ `WebFetch`
- Agent 组件：`Skill` / `SlashCommand` / `Task` / `AskUserQuestion` 等

CLI 会把每次 `tool.use` 打印成“带摘要”的人类可读格式（会显示它要读哪个文件/列哪个目录/搜索什么 query/执行什么 command），`tool.result` 也会输出精简摘要，并做 best-effort 的密钥脱敏。

## Skills（技能系统）

技能文件是 `SKILL.md`，会从多个 root 扫描并按“越本地优先级越高”的规则覆盖：

1) `OPENAGENTIC_AGENTS_HOME`（默认：`%USERPROFILE%\.agents`）
2) `OPENAGENTIC_SDK_HOME`（默认：`%USERPROFILE%\.openagentic-sdk`）
3) 项目目录
4) `./.claude`

本仓库提供了一些示例技能，位于 `./skills/`。

## Sessions（会话落盘位置）

每次运行会生成一个 session，默认落盘到：

- `OPENAGENTIC_SDK_HOME\sessions\<session_id>\`

文件包括：

- `meta.json`
- `events.jsonl`（JSONL 事件流，追加写）

设计目标是：人类用通用工具（文本查看/grep）就能排障与回溯。

## 在线 E2E（真实联网）

想验证“真实网络 + 真实 key”的全链路效果：

```powershell
.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E
```

说明：
- 需要 `.env` 里配置好 OpenAI key + model（以及可选 Tavily）。
- 开启 `-EnableProxy` 时会走本机代理。

## 常见问题（Troubleshooting）

### 401 / “Missing API key”

- 检查项目目录下的 `.env` 是否存在且包含 `OPENAI_API_KEY`。
- 如果你走网关，可能需要 `OPENAI_API_KEY_HEADER=x-api-key`（或你网关要求的 header）。

### rebar3 / escript.exe 找不到

先在同一个终端里执行环境脚本：

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

### 输出太密 / 眼睛疲劳

- 长回答建议用 `--no-stream`（更利于排版，也能启用 Markdown 渲染）。
- 颜色不兼容就用 `--no-color` 或 `NO_COLOR=1`。
