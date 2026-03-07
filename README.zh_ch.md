# openagentic-sdk-erlang（中文说明）

英文说明见：[`README.md`](README.md)

`openagentic-sdk-erlang` 是 `openagentic-sdk-kotlin` 的 Erlang/OTP 平行版本。
它现在已经不只是一个空壳 SDK，而是一套能在 BEAM 上本地跑起来的 agent runtime、workflow 控制面和轻量 Web UI。

## 当前功能现状

截至 **2026 年 3 月 7 日**，代码里已经落下来的能力包括：

- **Runtime 入口**：`openagentic_sdk:query/2` 与 `openagentic_runtime:query/2`
- **默认 Provider**：OpenAI Responses HTTP + SSE streaming
- **协议切换**：支持 `--protocol responses|legacy` 切到 OpenAI Chat Completions legacy 模式
- **本地优先会话落盘**：`meta.json` + append-only `events.jsonl`
- **会话续跑**：支持 `resume_session_id` 与 Responses 的 `previous_response_id`
- **统一时间上下文**：默认注入 `Asia/Shanghai`（东八区）时间信息到 system prompt 和 session metadata
- **权限门禁（HITL）**：`default` 模式下自动放行安全只读工具
- **内置工具集**：`AskUserQuestion`、`Read`、`List`、`Write`、`Edit`、`Glob`、`Grep`、`Bash`、`WebFetch`、`WebSearch`、`Skill`、`SlashCommand`、`NotebookEdit`、`LSP`、`TodoWrite`、`Task`
- **Skills 系统**：支持多 root 扫描 `SKILL.md`，并解析 `summary`、`checklist`、front matter
- **SlashCommand**：兼容 `.opencode/commands` 与 `.claude/commands` 模板
- **子 agent 工具**：`Task` 已内置 `explore` / `research` 两个 subagent
- **Workflow engine**：JSON DSL 驱动，支持 guards、output contracts、每步 tool policy、fanout/join、retry policy、step session 恢复
- **Workflow manager**：支持 continue 排队、cancel、watchdog 检测 stalled、`resumed_from_stalled`
- **本地 Web 控制面**：支持 workflow start/continue/cancel、问题回答、workspace 读取、会话原地续聊、健康检查、SSE 事件流
- **Hooks 与 tool output artifacts**：支持 `hook.event`、`HookBlocked`、大输出外置 artifact
- **WebFetch 安全策略**：阻断 localhost / 私网风格目标，并输出 `markdown` / `text` / `clean_html`
- **WebSearch 后端**：优先 Tavily；没配 key 时回退到 DuckDuckGo HTML 抓取
- **离线单测覆盖**：runtime、provider、session、CLI、workflow、tools、skills、web runtime、time context 等都有覆盖

本地刚跑过的验证结果：

- `rebar3 eunit` -> **185 tests, 0 failures**（验证时间：**2026-03-07**）

## 仓库结构

```text
apps/openagentic_sdk/
  src/
    openagentic_sdk.erl               SDK 公共入口
    openagentic_runtime.erl           tool-loop runtime
    openagentic_cli.erl               CLI 入口
    openagentic_workflow_dsl.erl      JSON DSL 加载与校验
    openagentic_workflow_engine.erl   workflow 执行引擎
    openagentic_workflow_mgr.erl      排队 / cancel / stalled 管理
    openagentic_web*.erl              本地 Web 服务与 API
    openagentic_tool_*.erl            内置工具
    openagentic_skills.erl            SKILL.md 扫描与索引
  test/
    *_test.erl                        eunit 测试
  priv/
    toolprompts/                      工具提示模板
    web/                              静态 Web UI
workflows/
  three-provinces-six-ministries.v1.json
  prompts/
scripts/
  erlang-env.ps1
  e2e-online-suite.ps1
  e2e-web-online.ps1
  kotlin-parity-check.ps1
docs/
  spec/                               workflow DSL 与 agent-host 协议
  design/ analysis/ plans/            设计文档与计划文档
```

## 架构概览

### 主入口

- SDK 门面：`apps/openagentic_sdk/src/openagentic_sdk.erl`
- Runtime / tool loop：`apps/openagentic_sdk/src/openagentic_runtime.erl`
- CLI：`apps/openagentic_sdk/src/openagentic_cli.erl`
- Workflow DSL 校验：`apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
- Workflow engine：`apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
- Workflow manager / watchdog：`apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
- Web server：`apps/openagentic_sdk/src/openagentic_web.erl`
- Skills 索引：`apps/openagentic_sdk/src/openagentic_skills.erl`
- Tool registry / schema：`apps/openagentic_sdk/src/openagentic_tool_registry.erl`、`apps/openagentic_sdk/src/openagentic_tool_schemas.erl`

### 数据流

```text
CLI / Web UI / Workflow API
        -> runtime 或 workflow engine
        -> provider 请求 + SSE / 模型输出解析
        -> permission gate
        -> tool registry -> tool modules
        -> session store 追加事件
        -> Web SSE / CLI formatter / workspace readers
```

### 持久化约定

默认的本地优先路径：

- Session 根目录：`OPENAGENTIC_SDK_HOME\sessions\<session_id>\`
- Session 文件：
  - `meta.json`
  - `events.jsonl`
- Skills root（越本地优先级越高）：
  - `OPENAGENTIC_AGENTS_HOME`（默认：`%USERPROFILE%\.agents`）
  - `OPENAGENTIC_SDK_HOME`（默认：`%USERPROFILE%\.openagentic-sdk`）
  - 项目根目录
  - `project/.claude`
- SlashCommand 模板：
  - `project/.opencode/commands/*.md`
  - `project/.claude/commands/*.md`
  - `%USERPROFILE%\.config\opencode\commands\*.md`

## 环境要求

- Erlang/OTP 28
- `rebar3`
- 推荐使用 Windows PowerShell 7.x
- 中国大陆网络环境通常需要代理（本仓库默认本机代理是 `127.0.0.1:7897`）

## 快速开始（Windows PowerShell）

### 1）准备 Erlang 环境和 E 盘缓存目录

```powershell
# 需要代理
. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify

# 不需要代理
# . .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

这个脚本会设置：

- `ERLANG_HOME=E:\lang\erlang`
- `REBAR_BASE_DIR=E:\erlang\rebar3`
- `REBAR_CACHE_DIR=E:\erlang\rebar3\cache`
- `HEX_HOME=E:\erlang\hex`

### 2）跑离线单测

```powershell
rebar3 eunit
```

### 3）进入 Erlang shell

```powershell
rebar3 shell
```

进入 shell 后可以这样跑：

```erlang
%% 单轮 query
openagentic_cli:main(["run", "你好，Erlang!"]).

%% 交互式聊天
openagentic_cli:main(["chat"]).

%% workflow（JSON DSL）
openagentic_cli:main([
  "workflow",
  "--dsl", "workflows/three-provinces-six-ministries.v1.json",
  "请规划并完成 X"
]).

%% 本地 Web UI / 控制面
openagentic_cli:main(["web"]).
```

默认 Web 地址：`http://127.0.0.1:8088/`

## CLI 当前能力面

`openagentic_cli:main/1` 目前提供四个命令：

- `run`：单次 prompt / 单次 session
- `chat`：交互式对话，并可续接已有 session
- `workflow`：跑 JSON DSL workflow
- `web`：启动本地 Cowboy Web UI + API

高价值参数：

- `--model <name>`
- `--base-url <url>`
- `--api-key <key>`
- `--protocol <responses|legacy>`
- `--max-steps <1..200>`
- `--stream` / `--no-stream`
- `--permission <bypass|deny|prompt|default>`
- `--project-dir <path>`
- `--session-root <path>`
- `--resume-session-id <sid>`
- `--dsl <path>`（给 `workflow`）
- `--web-bind <ip>` / `--web-port <port>`（给 `web`）
- `--render-markdown` / `--no-render-markdown`
- `--color` / `--no-color`

## Workflow engine：现在已经具备什么

workflow 子系统现在已经不是占位实现了，代码里已经支持：

- JSON DSL 加载与校验
- step role + prompt file
- output contract（`decision`、`markdown_sections`、`json_object` 等）
- guard 检查
- 每步独立 tool policy allow/deny
- step session 与 workflow session 的事件桥接
- 多部并行的 fanout/join
- provider transient error 的 retry policy
- workflow 仍在运行时，`continue` 消息可排队
- cancel 与 status 查询
- watchdog 检测 stalled，并把 `stalled` 状态写回 session

默认示例 DSL：

- `workflows/three-provinces-six-ministries.v1.json`

## Web UI / API

当前本地 Web 服务提供这些路由：

- `GET /` -> 静态 Web UI
- `POST /api/cases` -> 从已完成的 workflow session 创建 `case` 与首个 `deliberation_round`
- `GET /api/cases/:case_id/overview` -> 读取案卷总览（轮次、候选任务、正式任务、内邮）
- `POST /api/cases/:case_id/candidates/extract` -> 从该轮朝议 transcript 抽取 `monitoring_candidate`
- `POST /api/cases/:case_id/candidates/:candidate_id/approve` -> 将候选任务生效为 `monitoring_task` 与首个 `task_version`
- `POST /api/cases/:case_id/candidates/:candidate_id/discard` -> 废弃候选任务
- `GET /api/cases/:case_id/tasks/:task_id/detail` -> 读取任务详情（定义、版本、授权状态、credential binding）
- `POST /api/cases/:case_id/tasks/:task_id/credential-bindings` -> 为任务创建或更新一个 `credential_binding`
- `POST /api/cases/:case_id/tasks/:task_id/activate` -> 在授权条件满足后激活任务
- `POST /api/workflows/start`
- `POST /api/workflows/continue`
- `POST /api/workflows/cancel`
- `POST /api/workspace/read`
- `POST /api/questions/answer`
- `POST /api/sessions/:sid/query` -> 围绕既有治理 / runtime session 原地继续对话
- `GET /api/sessions/:sid/events` -> SSE 追踪 session 事件
- `GET /api/health`

这套 Web UI 是 local-first 的，不依赖额外数据库，而是直接基于 session 文件工作。

本次 Phase 1 新增的治理元数据落在 `cases/<case_id>/...`，而会话 transcript 仍继续保留在 `sessions/<session_id>/...`。

现在案卷治理页已经把 `review_session_id` / `governance_session_id` 接成可打开的聊天式治理入口：通过 `view/governance-session.html` 可以继续围绕同一条治理线审议候选、跟进生效后的正式任务。

Phase 1 现在也补上了 `view/task-detail.html`：可查看任务定义、版本历史、空态运行/交付物区、授权状态，并通过独立的授权接驳表单维护 `credential_binding`，只保存 `material_ref` 引用而不把敏感材料本体写进任务主 JSON。

## 工具与安全行为

### 权限默认行为

在 `default` 模式下，以下工具在 schema 合法时默认视为安全：

- `List`
- `Read`
- `Glob`
- `Grep`
- `WebFetch`
- `WebSearch`
- `Skill`
- `SlashCommand`
- `AskUserQuestion`

如果 `Write` / `Edit` 的目标路径能被解析到 workspace 内，也可以自动放行。其余工具会走 prompt 模式。

### 一些值得知道的工具行为

- `Read` 支持 offset + 行号分页
- `List` 用于先发现文件再 `Read` / `Grep`
- `Glob` / `Grep` 支持递归匹配和稳定排序
- `WebFetch` 可输出 `markdown` / `text` / `clean_html`
- `WebSearch` 优先 Tavily，没配 key 时回退 DuckDuckGo HTML
- `Skill` 会返回 `SKILL.md` 的元数据和正文
- `SlashCommand` 会从项目、本地和全局根查找命令模板
- `Task` 可拉起内置 `explore` / `research` 子 agent
- 大 tool output 可以被外置成 artifact 文件，并返回 truncated wrapper
- hooks 可以写 `hook.event`，也能用 `HookBlocked` 直接阻断工具调用

## 配置（.env）

CLI 会从解析后的项目目录读取 `.env`。
不要提交真实密钥。

最小示例：

```dotenv
OPENAI_API_KEY=your_key_here
MODEL=gpt-4.1-mini
```

常用变量：

- `OPENAI_API_KEY`
- `OPENAI_MODEL` 或 `MODEL`
- `OPENAI_BASE_URL`
- `OPENAI_API_KEY_HEADER`
- `OPENAI_STORE`
- `OPENAGENTIC_SDK_HOME`
- `OPENAGENTIC_AGENTS_HOME`
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `TAVILY_API_KEY`
- `TAVILY_URL`

## 测试与验证

### 离线

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
rebar3 eunit
```

### 可选在线套件

```powershell
.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E
.\scripts\e2e-web-online.ps1 -EnableProxy -SkipRebar3Verify -E2E
```

### Kotlin parity 辅助检查

```powershell
.\scripts\kotlin-parity-check.ps1
```

## 规范与设计文档

- Workflow engine 规范：`docs/spec/workflow-engine.md`
- Workflow engine 中文：`docs/spec/workflow-engine.zh_ch.md`
- Agent-host 协议：`docs/spec/agent-host-protocol.md`
- Agent-host 中文：`docs/spec/agent-host-protocol.zh_ch.md`
- Workflow DSL schema：`docs/spec/workflow-dsl-schema.md`
- Workflow DSL schema 中文：`docs/spec/workflow-dsl-schema.zh_ch.md`

## 常见问题

### `401` / 缺 API key

- 确认项目目录下存在 `.env`
- 确认 `OPENAI_API_KEY` 已设置
- 如果你走网关，确认 `OPENAI_API_KEY_HEADER` 配对正确

### `rebar3` 或 Erlang 找不到

先在同一个终端里执行：

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

### 输出太密

- 长回答建议用 `--no-stream`
- 终端不支持 ANSI 就用 `--no-color` 或 `NO_COLOR=1`
- 非流式模式下保留 `--render-markdown`

### WebSearch 结果偏弱

- 配置 `TAVILY_API_KEY` 会明显更稳
- 不配 Tavily 时会退回 DuckDuckGo HTML 抓取
