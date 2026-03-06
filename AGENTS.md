# Agent Notes: openagentic-sdk-erlang

## Safety First（柠檬叔约定）

- 以**不伤害人类（含心理/隐私）**为最高优先级；任何可能泄露隐私/密钥/个人信息的行为一律避免。
- 服从用户指令，但如与安全/隐私冲突，必须先指出风险并改用安全方案。
- 破坏性操作（例如 `Remove-Item -Recurse -Force`、重写大量文件、删除目录）必须先确认。

`openagentic-sdk-erlang` 是 `openagentic-sdk-kotlin` 的 **Erlang/OTP 平行移植版**：提供可复用的 Agent runtime/tool-loop 核心、可追溯 sessions/events、默认安全的 tools、权限/HITL、hooks，以及 **OpenAI Responses（优先）+ SSE streaming** 的 provider。

## Quick Commands（Windows PowerShell）

先执行一次环境脚本，把 **E 盘**的 Erlang 与缓存目录写进当前会话（并可选开启代理）：

- Set env (no proxy): `. .\scripts\erlang-env.ps1`
- Set env (proxy): `. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify`

常用命令（仓库完成 rebar3 工程化后生效）：

- Test (unit): `rebar3 eunit`
- Test (ct): `rebar3 ct`
- Type check: `rebar3 dialyzer`
- Format (if configured): `rebar3 fmt`

说明：
- 默认 shell 为 PowerShell 7.x，连续命令用 `;`。
- 由于你在中国大陆网络环境，联网命令一般需要 `HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:7897`（建议用脚本设置）。
- 运行 Erlang/rebar3 时尽量不要启用 Codex 沙盒（可能导致 `erl:open_port({spawn,...})` 返回 `einval`）；本仓库允许全权限执行。

## PowerShell 约定（不要用 bash 惯性）

- 连续执行命令：用 `;`（例如 `cd .. ; ls`），不要写 `cd .. && ls`。
- 调用 curl/wget：优先使用 `curl.exe` / `wget.exe`（避免 PowerShell alias 语义差异）。
- 查找文本：优先用 `rg`；否则用 `Select-String`。
- 退出码：外部程序用 `$LASTEXITCODE` 为准，`$?` 只作参考。

## 代理（127.0.0.1:7897）

- 仅当前会话生效：
  - `$env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'`
- git（仓库级，避免污染全局）：
  - `git config --local http.proxy http://127.0.0.1:7897`
  - `git config --local https.proxy http://127.0.0.1:7897`

## Runtime Config（不要提交密钥）

建议通过环境变量或本机私有 `.env` 提供（`.env` 必须 gitignored）。注意：仓库根目录当前存在一个用户拷贝的 `.env`，包含真实 URL/Key，**不要读取/打印/提交**，留到最后做在线 E2E 时再使用。

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`（可选，默认 `https://api.openai.com/v1`）
- `MODEL`（例如 `gpt-4.1` / `gpt-4.1-mini`，以你的实际为准）
- 代理（可选）：`HTTP_PROXY` / `HTTPS_PROXY`（注意：优先用大写变量名）

## Architecture Overview

### 目标对齐（与 Kotlin 版一致的核心概念）

- `query(prompt, options)`：产出事件流（或事件列表），并将 events 持久化到 session store
- Tool loop：模型输出 → tool calls → tool outputs → 下一轮模型输入 → `Result`
- Sessions：`meta.json` + `events.jsonl`（JSONL 追加写；尽量可修复尾部截断）
- Permissions/HITL：默认只放行少数“安全工具”；其余需 prompt/deny/bypass 可配置
- Provider：**OpenAI Responses（优先）**；支持 **SSE streaming** 与可重试策略

### 计划目录结构（建议）

> 现在仓库还很空，后续实现时按需落地即可。

- `apps/openagentic_sdk/`：主库（rebar3 app）
  - `src/`：核心实现
  - `test/`：eunit
  - `priv/fixtures/`：离线协议/响应夹具（SSE 流、JSON 示例）
- `apps/openagentic_sdk_ct/`：common_test（可选，用于更接近 E2E 的离线门禁）

### 数据流（目标形态）

```
User prompt
  -> runtime/tool_loop
    -> provider (OpenAI Responses SSE)
      -> tool_use events
        -> permission gate
          -> tool runner
            -> tool_result/tool_output
  -> assistant_message/result
  -> file_session_store (events.jsonl)
```

### Provider（OpenAI Responses + SSE）

- 协议优先：对齐 Kotlin 版 `OpenAIResponsesHttpProvider` 的行为与事件语义
- SSE：实现可增量解析（逐行/逐事件），保证断线可恢复、错误可归因（含原始片段）
- 测试：SSE decoder/事件解析必须用离线 fixtures 覆盖（不依赖真实网络）

## 当前进度（续上用）

- 核心（已落地）：Responses + SSE provider、session store（`meta.json` + `events.jsonl`）、runtime/tool-loop、permission gate、基础安全文件工具。
- 已对齐：workflow step 可显式声明 `retry_policy`；仅对明确开启 `transient_provider_errors` 的幂等 step 自动重试 provider timeout / stream transient failures，默认不对副作用 step 盲目重跑。
- 已对齐：`openagentic web` 内部服务由 `openagentic_web_runtime_sup` 独立监督；`openagentic_web_q` / `openagentic_workflow_mgr` 不再直接绑到 shell 调用方，watchdog 触发后会把 `stalled` 写入 session，并在 Web API 中区分 `queued` / `resumed_from_stalled`。
- 正在对齐：`Skill` / `SlashCommand`（对齐 Kotlin 的 skills roots precedence + `/skills` 等命令）。
- 已解决：`rebar3 eunit` 的 skills 相关失败（根因是 skills 文件扫描里误用 `lists:flatten/1` 把“路径列表”拍平为“字符列表”）。现已全绿。
- 已对齐：`SlashCommand`（opencode commands 模板加载 + `${args}`/`${path}` 渲染）与 `Skill`（summary/checklist/front-matter 解析 + 输出字段）；`rebar3 eunit` 全绿后再继续扩展工具集。
- 已提升模型可用性：`Skill` tool schema 的 `description` 会注入当前可用 skills 列表（减少模型猜 skill 名字）。
- 已提升模型可用性：`SlashCommand` tool schema 的 `description` 会注入当前可用 commands 列表（减少模型猜命令名）。
- 已提升模型可用性：`Read`/`Glob`/`Grep` tool schema 的 `description` 注入项目上下文与用法提示（更稳定地产生可执行入参）。
- 已提升模型可用性：`Skill`/`SlashCommand` tool schema 的 `description` 注入项目上下文与用法提示（更少瞎编 name/args）。
- 已对齐工具行为：`Glob`/`Grep` 支持 `**` 递归 glob（例如 `src/**/*.erl`），避免“按提示调用但结果不符合预期”。
- 已对齐工具行为：`Glob` 支持 `root/path` 指定基目录、`max_matches/max_scanned_paths` 限流，并返回 `count/truncated/root` 等元数据（对齐 Kotlin，避免大仓库扫描失控）。
- 已提升模型可用性：新增 `List` 工具（递归列目录树 + 常见目录忽略 + `limit` 截断），默认放行，便于模型先“发现文件”再 `Read/Grep/Glob`。
- 已提升模型可用性：`Grep` 输出包含 `relative_path` 且按（`relative_path`，`line`）稳定排序，便于模型直接 follow-up `Read`。
- 已提升模型可用性：`Read` 支持 `offset` 1-based + 行号输出（分页更可引用），并返回 `file_size/bytes_returned/truncated` 元数据。
- 已对齐：Runtime hooks（`PreToolUse`/`PostToolUse`）+ `hook.event` 事件写入，支持阻断工具调用（`HookBlocked`）。
- 已对齐：Tool output artifacts（超大 tool output 外置到 artifact 文件 + truncated wrapper：`artifact_path/preview/hint`）。
- 已对齐：`WebFetch`（clean_html/markdown 清洗、链接绝对化、私网/localhost/IPv6 拦截）+ 离线 contract tests 门禁。
- 已对齐：`Glob/Grep/Bash` 对 `root/workdir` 不存在/非目录的失败路径映射为 Kotlin 风格异常类型（避免落到 `ToolError`）。
- ✅ 2026-03-04：用户明确不需要 `lsp` 的 Kotlin 扩展能力对齐（builtin registry/root resolver 等），保留最小可用实现即可。

## Kotlin Parity 对齐工作流（强制）

当任务目标是“对齐 openagentic-sdk-kotlin / parity backlog”时，必须严格按以下顺序执行（防止清单丢失与文档漂移）：

1) 扫描差异（Kotlin ↔ Erlang），形成差异点列表
2) 先把差异点逐条写入 `docs/plans/2026-03-04-kotlin-parity-backlog.md`，并以 `- [ ]` 形式作为可勾选 checklist（每条都要有 DoD）
3) 只实现一个差异点（不要并行开多条）
4) 该差异点完成后立即跑门禁（至少对应模块的 `rebar3 eunit` / `scripts/kotlin-parity-check.ps1` 等证据）
5) 门禁通过后立刻回写 backlog：把对应项从 `- [ ]` 改为 `- [x]`，并补上落地文件路径 + Evidence（命令与关键输出摘要）
6) 进入下一条差异点

注意：
- **禁止**“先改代码再补 backlog”；也**禁止**“全部改完最后一次性回写 backlog”。
- 若遇到阻塞/失败，必须第一时间把“失败现象 + 复现命令 + 预期/实际”写回 backlog（避免 compact context 后遗忘）。

## Code Style & Conventions（Erlang）

- 语言：Erlang/OTP 28（本机安装在 `E:\lang\erlang`）
- 命名：模块 `openagentic_*` 前缀；record/map keys 使用 `snake_case`（尽量与 JSON 字段一致）
- JSON：优先统一一个编码/解码层（避免全项目散落 `jsx/jiffy` 直接调用）
- 错误：对外 API 返回 `{ok, Value} | {error, Reason}`；日志里保留可定位字段（request_id、session_id、tool_use_id）
- 变更策略：小步提交；每次行为变化必须补齐测试/fixtures

## Safety & Conventions（不要让大文件落到 C 盘）

- **OTP/工具安装位置（已约定）**：
  - `ERLANG_HOME=E:\lang\erlang`
  - `rebar3=E:\lang\bin\rebar3.cmd`
- **缓存/依赖目录必须在 E 盘**：
  - `REBAR_BASE_DIR=E:\erlang\rebar3`
  - `REBAR_CACHE_DIR=E:\erlang\rebar3\cache`
  - `HEX_HOME=E:\erlang\hex`
- **Session / workflow 运行目录（已确认）**：
  - `OPENAGENTIC_SDK_HOME=E:\openagentic-sdk`
  - workflow / runtime sessions 默认落在 `E:\openagentic-sdk\sessions`
  - 当用户给出 `workflow_session_id` 时，优先去 `E:\openagentic-sdk\sessions\<workflow_session_id>` 查 `meta.json` / `events.jsonl`
- 禁止把真实密钥写进仓库、日志、测试夹具；`.env` 必须保持本地化并 gitignored。
- 任何批量删除/破坏性操作（`Remove-Item -Recurse -Force` 等）必须先征得用户确认。

## Testing Strategy（确定性门禁）

- 单元测试：eunit 覆盖核心纯逻辑（JSON、SSE 解析、权限判断、events 序列化）
- 离线 E2E：用 fixtures 模拟 provider streaming（不要在 PR 级测试里打真实 OpenAI）
- 真联网 E2E（可选）：必须显式开关（例如 `OPENAGENTIC_E2E=1`），并且默认关闭

## Scope & Precedence

- 根目录 `AGENTS.md` 默认适用全仓库。
- 子目录如出现 `AGENTS.md`，其规则覆盖本文件在该子树内的同主题规则。
- 用户在聊天中的显式指令优先级最高。

## 完成后提醒（默认开启）

每次任务完成后，使用 `apn-pushtool` 给手机发送一条简短推送（标题：repo 名；正文：≤10 字梗概），不要包含任何密钥或敏感信息。如果本机未配置或推送失败，需在回复中说明失败原因并继续推进其它工作。
