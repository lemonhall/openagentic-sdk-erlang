# Kotlin Parity Backlog（Erlang SDK）

> **Goal:** 将 `openagentic-sdk-erlang` 的内置工具与 `openagentic-sdk-kotlin` 在“模型可用性”相关的 **5 个方面**完全对齐，并以脚本 + 测试作为**绝对门禁**。
>
> Kotlin 参考源码：
> - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\*`
> - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\permissions\PermissionGate.kt`
> - `E:\development\openagentic-sdk-kotlin\src\main\resources\me\lemonhall\openagentic\sdk\toolprompts\*.txt`

## 五个方面（DoD，全部无差异才算通过）

1. **ToolPrompts 资源对齐**
   - toolprompts 文件列表与文件内容（逐字节/仅允许换行归一化）与 Kotlin 完全一致
   - Erlang 侧 prompt 注入与变量替换策略对齐（含 `date`、`available_skills` 等特殊注入）

2. **Tool Schemas 对齐**
   - OpenAI tool/function schema：`name`、`properties`、`required`、`additionalProperties` 等关键字段与 Kotlin 语义一致
   - 对于有 toolprompt 资源的工具：description/prompt 注入策略与 Kotlin 一致

3. **PermissionGate（safe-tools）对齐**
   - 默认 safe-tools 集合与 Kotlin 完全一致（不多不少）

4. **默认工具集合（coverage）对齐**
   - Erlang runtime 默认注册的工具集合与 Kotlin CLI 默认注册的工具集合完全一致（不多不少）
   - 每个工具最小可用：参数可解析、输出结构稳定、错误可归因

5. **工具行为与错误语义对齐（最终门禁）**
   - 对所有默认工具：输入兼容、输出字段、错误类型/消息（在允许范围内）与 Kotlin 保持一致
   - 不允许“看起来能用但细节不同”：模型会被细节差异误导

---

## Backlog（按执行顺序；勾选表示已通过门禁）

### A. ToolPrompts（资源 + 注入）

- [x] Kotlin `toolprompts/*.txt` 同步到 `apps/openagentic_sdk/priv/toolprompts/*.txt`
- [x] Erlang 侧统一从 `priv/toolprompts/<name>.txt` 读取，并支持 `${var}` 与 `{{var}}` 替换
- [x] `Skill` 的 `available_skills` 注入策略对齐 Kotlin（写入 `<available_skills>...</available_skills>`）

### B. Schemas（snapshot 对齐）

- [x] `openagentic_tool_schemas.erl` 的 properties/required 与 Kotlin snapshot 对齐（容许多别名字段以兼容模型）
- [x] 有 toolprompt 资源时：优先用 toolprompt 覆盖 tool description（与 Kotlin 资源一致）
- [x] `SlashCommand` 不注入 toolprompt（Kotlin 无该 prompt）

### C. PermissionGate（safe-tools）

- [x] `safe_tools()` 集合与 Kotlin 完全一致：`Read/Glob/Grep/Skill/SlashCommand/AskUserQuestion`

### D. 默认工具集合（coverage）

- [x] Erlang runtime 默认注册集合与 Kotlin CLI 默认集合一致（额外补齐 `Task/AskUserQuestion`）
- [x] 对齐工具覆盖面：`Read/List/Write/Edit/Glob/Grep/Bash/WebFetch/WebSearch/NotebookEdit/lsp/Skill/SlashCommand/TodoWrite/Task/AskUserQuestion`

### E. 工具实现（最小可用）

- [x] `Write/Edit/Bash/WebFetch/WebSearch/NotebookEdit/lsp/TodoWrite/Task` 已落地最小可用实现并接入 runtime
- [x] 相关 eunit 已调整，避免扫描用户真实目录造成超时；`rebar3 eunit` 已全绿

### F. 绝对门禁（最终对齐检查，未通过前禁止汇报）

- [x] 运行 `.\scripts\kotlin-parity-check.ps1`（对 prompts / safe-tools / default-tools / schemas 做硬对齐）
- [x] 补齐“工具行为与错误语义”门禁：基于 Kotlin 工具实现写离线用例（覆盖核心工具：Read/List/Write/Edit/Glob/Grep/Skill/SlashCommand/TodoWrite/NotebookEdit/WebFetch/WebSearch/Bash + AskUserQuestion/Task runtime 语义）
- [x] 最终复核：`rebar3 eunit` 全绿 + `kotlin-parity-check OK`，并二次确认 5 个方面无差异

---

## 姊妹项目复扫（openagentic-sdk-kotlin）发现的差异点（需纳入下一轮门禁）

> 说明：以下差异点来自对 Kotlin 源码二次扫描（工具实现/错误语义/安全细节），**不在当前 `kotlin-parity-check.ps1` 覆盖范围内**。

### 1) Path Resolver（symlink escape）差异（高风险）

- Kotlin：`resolveToolPath()` 会做 **symlink escape** 防护（canonicalize + realPath，拒绝通过符号链接越狱）。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\ToolPathResolver.kt`
- Erlang：✅ 已补齐 `openagentic_fs:resolve_tool_path/2` 的 symlink escape 防护（nearest-existing prefix canonicalize + link resolution），并新增 eunit 覆盖（`projectRoot/link -> outside`）。
  - `apps/openagentic_sdk/src/openagentic_fs.erl`
  - `apps/openagentic_sdk/test/openagentic_fs_tools_test.erl`

### 2) 错误语义（exception 类型/消息）仍存在系统性差异（高优先）

- Kotlin runtime：工具抛出的异常类型会被写入 `tool.result.error_type = e::class.simpleName`，错误信息来自 `e.message`。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
- Erlang runtime：✅ 已将核心工具的常见失败路径统一映射为 Kotlin 风格的 `{kotlin_error, Type, Msg}`（避免落到 `ToolError`），并补齐离线 contract tests 做门禁。
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`
  - `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`

### 3) LSP 工具能力差异（较大缺口）

> ✅ 2026-03-04：用户明确表示 **不需要 LSP 的 Kotlin 扩展能力对齐**（builtin registry/root resolver 等），本条差异点从“扩展门禁”中移除。

- 保留现状：Erlang `lsp` 作为最小可用实现即可（OpenCode config + stdio JSON-RPC）。

### 4) WebFetch 清洗/Markdown 语义差异（中-高优先）

- Kotlin：`WebFetch` 使用 jsoup + safelist + boilerplate stripping + absolutize links + html2md（markdown 模式）。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\WebFetchTool.kt`
- Erlang：✅ 已补齐“去 boilerplate + 主内容选择 + allowlist + 链接绝对化 + Markdown 规范化”的最小等价实现，并新增离线门禁用例确保输出稳定。
  - `apps/openagentic_sdk/src/openagentic_tool_webfetch.erl`
  - `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`

### 5) WebSearch（DDG fallback）失败行为差异（中优先）

- Kotlin：DDG fallback 的 HTTP GET 若 `status>=400` 会抛异常（RuntimeException），并会影响 tool.result 的 error_type/error_message。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\WebSearchTool.kt`
- Erlang：✅ 已对齐 DDG fallback 的 `HTTP>=400` 失败语义为 `RuntimeException`，并新增离线门禁用例（transport 模拟）。
  - `apps/openagentic_sdk/src/openagentic_tool_websearch.erl`
  - `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`

### 6) Runtime Hook / Tool Output Artifacts 差异（中-高优先）

- Kotlin runtime：
  - 支持 pre/post hooks，可阻断 tool use（`error_type = HookBlocked`）。参考：
    - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
  - 对超大 tool output 支持 externalize 到 artifact 文件，并用 wrapper 返回 `artifact_path/preview/hint`（模型可继续用 `Read` 读取）。参考：
    - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
- Erlang runtime：✅ 已补齐 hooks（pre/post，可 block，产出 `hook.event`，并对齐 `HookBlocked`）与 output externalization（artifact 文件 + truncated wrapper），并新增离线门禁测试。
  - `apps/openagentic_sdk/src/openagentic_hook_engine.erl`
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`
  - `apps/openagentic_sdk/test/openagentic_tool_loop_test.erl`

### 7) WebFetch 私网/本机地址拦截差异（IPv6/保留段覆盖）（高风险）

- Kotlin：`WebFetch` 通过 `InetAddress.getAllByName(host)` 做解析，并用 `isAnyLocalAddress/isLoopbackAddress/isLinkLocalAddress/isSiteLocalAddress` 等判断拦截；因此 **IPv4/IPv6** 都会覆盖。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\WebFetchTool.kt`
- Erlang：✅ 已增加 IPv6 解析与拦截（`inet6` + ULA/link-local/loopback/unspecified + IPv4-mapped），并补齐离线门禁覆盖：`localhost`、`.localhost`、IPv4 私网、IPv6 loopback/ULA。
  - `apps/openagentic_sdk/src/openagentic_tool_webfetch.erl`
  - `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`

### 8) Glob/Grep 对 root/path 不存在/非目录时的异常类型差异（中优先）

- Kotlin：`Glob/Grep` 依赖 Okio `listRecursively/list` 等 API；当 root 不存在或不是目录时，通常会抛出 I/O 异常（error_type 往往为 `FileNotFoundException`/`IOException` 等，message 由底层决定）。
- Erlang：✅ 已将 `root`/`base` 的“不存在/非目录”失败路径映射为 Kotlin 风格异常类型（避免 `{not_a_directory,...}` 落到 `ToolError`），并补齐离线门禁用例。
  - `apps/openagentic_sdk/src/openagentic_tool_glob.erl`
  - `apps/openagentic_sdk/src/openagentic_tool_grep.erl`
  - `apps/openagentic_sdk/src/openagentic_tool_bash.erl`
  - `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`
- DoD：将此类 I/O/路径失败统一纳入“错误语义系统性对齐”（见差异点 2），对齐到 Kotlin 的 `error_type`（至少 `FileNotFoundException`/`RuntimeException`）与可接受的 message 策略，并补齐失败路径用例。

---

## 下一轮扩展门禁（基于复扫差异点，全部通过后才算“最终无差异”）

- [x] `resolve_tool_path` symlink escape 防护 + 覆盖用例（差异点 1）
- [x] 错误语义系统性对齐（差异点 2 + 8）
- [x] WebFetch 清洗/markdown 语义对齐（差异点 4）
- [x] WebSearch DDG fallback 的 HTTP>=400 失败语义对齐（差异点 5）
- [x] Runtime hooks + tool output artifacts 对齐（差异点 6）
- [x] WebFetch 私网/本机拦截 IPv6 覆盖（差异点 7）

---

## 2026-03-04 复扫（非工具层：runtime/provider/sessions/cli）新增差异点

> 说明：本文前半部分的“工具层 parity”已通过门禁（见上文全部勾选）。本节是对 Kotlin 姊妹项目进行第三轮扫描后，发现的 **非工具层** 对齐缺口清单。
>
> Kotlin 参考：
> - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\RuntimeModels.kt`
> - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
> - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\providers\*`
> - `E:\development\openagentic-sdk-kotlin\docs\plan\v2-sessions-resume.md`
> - `E:\development\openagentic-sdk-kotlin\docs\plan\v4-compaction.md`
> - `E:\development\openagentic-sdk-kotlin\docs\plan\v4-cli-chat.md`

### 9) Sessions Resume（跨进程恢复会话）（高优先）

- Kotlin：支持 `resumeSessionId`，从 `events.jsonl` 恢复，并继续 append-only 写入；同时从历史 `result.response_id` 推导 `previousResponseId`。参考：
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v2-sessions-resume.md`
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\RuntimeModels.kt`
- Erlang：当前 `openagentic_runtime:query/2` 每次都会 `create_session/2`，尚无 `resume_session_id` 能力。
- DoD：
  - 支持 `resume_session_id`（或 `resumeSessionId`）参数：读取历史 events、推导 `previous_response_id`、并继续在同一 session 目录 append events
  - 增加“恢复上限”门禁：对齐 Kotlin 的 `resumeMaxEvents/resumeMaxBytes` 思路（避免大 session OOM/超时）

### 10) Provider Retry/Backoff + Retry-After（高优先）

- Kotlin：Provider 层具备确定性的 retry/backoff（含 `Retry-After` 解析与上限），用于抵抗瞬态网络/限流。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\RuntimeModels.kt`（`ProviderRetryOptions`）
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v1-index.md`（W4/W5/W6）
- Erlang：当前 provider 调用未实现通用 retry/backoff（除 “previous_response_id 失败重试一次” 的特例）。
- DoD：
  - 引入 provider retry options（maxRetries/initial/max/useRetryAfter）
  - 离线门禁：模拟 429/5xx/网络失败，验证重试次数与 backoff 上限稳定可测

### 11) Compaction（overflow + pruning）（高优先）

- Kotlin：具备 compaction pass（溢出保护 + tool output pruning + summary pivot），并新增事件 `user.compaction`、`tool.output_compacted`。参考：
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v4-compaction.md`
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\compaction\Compaction.kt`
- Erlang：尚无 compaction 模块/事件，模型上下文增长完全依赖 max_steps 截断。
- DoD：
  - 增加 compaction 事件与 transcript builder（含 marker/placeholder 策略对齐）
  - compaction pass 走 “tool-less provider call”，并把 summary 写入 `assistant.message(is_summary=true)`（或等价字段）作为 pivot

### 12) Provider 多协议兼容（Responses + Legacy + Anthropic）（中-高优先）

- Kotlin：Provider 抽象区分 `RESPONSES` 与 `LEGACY`，并实现：
  - OpenAI Responses（含 SSE streaming）
  - OpenAI Chat Completions（legacy）
  - Anthropic Messages
  参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\providers\ProviderModels.kt`
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v3-provider-compat.md`
- Erlang：当前仅实现 `openagentic_openai_responses`。
- DoD：
  - 定义 protocol-aware provider 行为（至少 Responses + Legacy 两条路径）
  - 将 tool schema 与 provider 形状转换纳入离线门禁（避免同名字段但形状差异）

### 13) Streaming / includePartialMessages（assistant.delta）（中优先）

- Kotlin：可选 `includePartialMessages=true`，将 provider streaming 的 text delta 以 `assistant.delta` 事件形式对外吐出（并且 session store 不落盘 delta）。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\RuntimeModels.kt`
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\sessions\FileSessionStore.kt`
- Erlang：当前 provider 虽以 SSE 收取，但 runtime 只在最终聚合后写 `assistant.message`，没有对外 streaming 事件。
- DoD：
  - 增加 streaming query（或回调）路径：能边收边吐 `assistant.delta`
  - 门禁：delta 不落盘（与 Kotlin 一致），并且最终 `assistant.message` 仍与聚合结果一致

### 14) Events schema（Result/RuntimeError/AssistantMessage）字段对齐（中优先）

- Kotlin：`result`/`runtime.error`/`assistant.message` 等事件字段更丰富（final_text/session_id/usage/provider_metadata/steps/is_summary/phase/error_type...）。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\events\Events.kt`
- Erlang：现有事件字段更精简（例如 `result` 只有 response_id/stop_reason；`runtime.error` 只有 message/raw）。
- DoD：
  - 统一事件字段口径：最小但可追溯（至少补齐 `final_text/session_id/usage/steps/error_type/phase`）
  - 离线门禁：events.jsonl schema snapshot（字段存在性 + 类型）保持稳定

### 15) CLI parity（run/chat/resume/permission/stream）（中优先）

- Kotlin：具备最小 CLI 与 chat REPL，并支持 `--resume`、`--permission`、`--stream`。参考：
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v3-cli.md`
  - `E:\development\openagentic-sdk-kotlin\docs\plan\v4-cli-chat.md`
- Erlang：当前无对等 CLI（仅作为库被调用/脚本测试）。
- DoD：
  - 提供最小可用 CLI（escript 或 rebar3 shell）以验证 runtime/tool-loop/provider 的真实体验
  - 覆盖 `resume/permission/stream`（若 streaming 已实现）

### 16) Built-in SubAgents（explore）（中优先）

- Kotlin：内置 `explore` 子任务（system prompt + allowedTools + 进度回调），可通过 `Task` 工具触发。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\subagents\BuiltInSubAgents.kt`
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\subagents\TaskRunners.kt`
- Erlang：已有 `Task` 工具与 `task_runner/task_agents` plumbing，但缺少 built-in agents 与默认 runner 组合。
- DoD：
  - 内置 `explore` agent 定义（prompt/allowed tools）与默认 task runner（可组合/可覆盖）
  - 门禁：子任务 session 与父 session 的 event 归因清晰（parent_session_id/parent_tool_use_id 等）

---

## 下一轮扩展门禁（非工具层，对齐 Kotlin runtime roadmap）

- [x] Sessions Resume：`resume_session_id` + previous_response_id 推导 + 限流（差异点 9）
- [x] Provider Retry/Backoff：含 `Retry-After`（差异点 10）
- [x] Compaction：overflow + pruning + summary pivot（差异点 11）
- [x] Provider 多协议：Responses + Legacy（至少 OpenAI Chat Completions）（差异点 12）
- [x] Streaming：`assistant.delta` + includePartialMessages（差异点 13）
- [x] Events schema：Result/RuntimeError/AssistantMessage 字段口径（差异点 14）
- [x] CLI：run/chat + resume/permission/stream（差异点 15）
- [x] Built-in SubAgents：explore（差异点 16）

---

## 第五轮扩展门禁（CLI 细节对齐）

- [x] CLI flags parity：`--no-stream/--max-steps/--context-limit/--reserved/--input-limit`（差异点 20）

---

## 第六轮扩展门禁（Provider/CLI 体验对齐；不含 LSP 扩展能力）

> 说明：本轮由 `docs/plans/2026-03-04-kotlin-vs-erlang-feature-matrix.md` 的“未打勾项”汇总而来；**LSP 扩展能力已明确不纳入对齐**。

- [x] Responses Provider：`store` 默认行为与 `--openai-store/--no-openai-store` 对齐（差异点 21）
- [x] Responses Provider：`api_key_header` / `apiKeyHeader` 对齐（差异点 22）
- [x] CLI：读取 `.env` + 补齐核心 flags（`--project-dir/--api-key/...`）（差异点 23）
- [x] Provider 扩展：Anthropic Messages（范围外可选，但 Kotlin 现有）（差异点 24）

---

## 执行记录（防 compact 丢清单）

### 2026-03-04（本轮累计进展）

> NOTE（环境 / Codex 沙盒）：在 Codex 默认 sandbox（`workspace-write`）里，Erlang 的 `erl:open_port({spawn,...})` 会返回 `einval`，从而导致 `rebar3` 依赖/编译阶段不稳定（rebar3 内部会用 `open_port` 去跑 `cmd/mklink`，以及 kernel 的 `inet_gethost` 也依赖 `open_port`）。切到 `require_escalated`（非沙盒）执行后，`open_port` 正常，`rebar3 eunit` 也能完整跑通（77 tests, 0 failures）。为了不被沙盒卡死，本轮门禁同时保留了“手工 `erlc` 编译 + `eunit:test(...)`”的离线验证手段。

#### ✅ 差异点 9：Sessions Resume（已完成）

- 落地：`openagentic_runtime:query/2` 支持 `resume_session_id`/`resumeSessionId`，并对齐 Kotlin：
  - 恢复时读取历史 `events.jsonl`，并从最近 `result.response_id` 推导 `previous_response_id`
  - 增加恢复限流：`resume_max_events`/`resumeMaxEvents` 与 `resume_max_bytes`/`resumeMaxBytes`（避免大 session OOM/超时）
  - 恢复时不重复写 `system.init`（与 Kotlin 一致）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_runtime_resume_test.erl`

#### ✅ 差异点 10：Provider Retry/Backoff（已完成）

- 落地：新增 `openagentic_provider_retry`，实现 Kotlin 风格的 retry/backoff + `Retry-After`：
  - 429 优先用 `Retry-After`（支持 `Nms` 与 `N` 秒），并对 wait 做上限 clamp（避免长 sleep/溢出）
  - 其他瞬态错误走指数退避（默认 initial=500ms，max=30s，maxRetries=6）
- 运行时接入：
  - `openagentic_runtime:call_model/1` 统一通过 retry wrapper 调用 provider（含“previous_response_id 失败移除后再试一次”的特例路径）
  - `openagentic_openai_responses` 非 SSE 响应改为 `{http_error, Status, Headers, Body}`，以便解析 `retry-after`
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_provider_retry_test.erl`

#### ✅ 差异点 13：Streaming / includePartialMessages（已完成）

- 落地：runtime 增加 `include_partial_messages=true` 时的增量 delta 回调链路：
  - provider 可通过 `on_delta` 回调上报码流增量
  - runtime 将增量映射为 `assistant.delta(text_delta=...)` 并通过 `event_sink` 吐出
  - delta **不写入** `events.jsonl`（与 Kotlin 的 session store 行为一致）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_partial_messages_test.erl`

#### ✅ 差异点 11：Compaction（已完成）

- Kotlin 对齐点：
  - overflow 判定：`total_tokens >= usable`（边界触发，严格对齐 Kotlin `wouldOverflow`）
  - pruning：按 Kotlin `selectToolOutputsToPrune` 逻辑执行（跳过最近 2 个 user turns；严格 `prunedTokens > minPruneTokens`；遇到 `tool.output_compacted`/`assistant.message(is_summary=true)` 作为扫描边界）
  - compaction pass：写入 `user.compaction(auto=true, reason="overflow")` + `assistant.message(is_summary=true)` summary pivot，并清空 `previous_response_id`
- 落地：
  - `apps/openagentic_sdk/src/openagentic_compaction.erl`
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`（eligible 逻辑对齐 Kotlin：legacy 或 `!supportsPreviousResponseId` 才触发 overflow auto-compaction）
  - `apps/openagentic_sdk/src/openagentic_model_input.erl`（marker question + tool output placeholder 注入）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_compaction_test.erl`

#### ✅ 差异点 12：Provider 多协议（已完成）

- Kotlin 对齐点：
  - 引入 `protocol = responses|legacy` 概念；legacy 走 OpenAI Chat Completions（Kotlin `ProviderProtocol.LEGACY`）
  - Responses-style input/tools 仍由 runtime 统一构建；legacy provider 在内部完成 input/tools 转换（对齐 Kotlin `OpenAIChatCompletionsHttpProvider` 的核心思路）
  - legacy 默认 `supports_previous_response_id=false`；只有 responses 才会 thread `previous_response_id`
- 落地：
  - `apps/openagentic_sdk/src/openagentic_provider_protocol.erl`（protocol 归一化）
  - `apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl`（Legacy provider）
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`（按 protocol 选择 provider + compactionEligible 口径对齐 Kotlin）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_provider_protocol_test.erl`
  - `apps/openagentic_sdk/test/openagentic_openai_chat_completions_test.erl`

#### ✅ 差异点 14：Events schema（已完成）

- Kotlin 对齐点：
  - 事件字段口径对齐 Kotlin `Events.kt`：`Result/RuntimeError/AssistantMessage/ToolResult` 的 snake_case 与 optional 字段省略策略（`explicitNulls=false`）
  - `Result.stop_reason/usage/response_id` 在 undefined/null/blank 时省略，避免写入 `"undefined"` 这类误导值
  - `ToolResult.output=null` 时省略 `output`
- 落地：
  - `apps/openagentic_sdk/src/openagentic_events.erl`
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`（Result 的 `response_id` 使用 state 里的 `previous_response_id`，与 Kotlin 一致）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_events_schema_test.erl`

#### ✅ 差异点 15：CLI parity（已完成）

- Kotlin 对齐点（按 `docs/plan/v3-cli.md` + `docs/plan/v4-cli-chat.md`）：
  - `run`：单次 prompt
  - `chat`：REPL 多轮（通过 `--resume` / 内部 session_id 续写）
  - `--permission`：bypass/deny/prompt/default
  - `--stream`：启用 `include_partial_messages`（responses provider 可增量打印 delta）
  - `--protocol`：responses|legacy
- 落地：
  - `apps/openagentic_sdk/src/openagentic_cli.erl`

#### ✅ 差异点 20：CLI flags parity（已完成）

- Kotlin 对齐点（参考 Kotlin CLI `Main.kt`）：
  - streaming 默认开启（增加 `--no-stream`）
  - `--max-steps <1..200>`
  - compaction flags：`--context-limit/--reserved/--input-limit`
- 落地：
  - `apps/openagentic_sdk/src/openagentic_cli.erl`
  - `apps/openagentic_sdk/test/openagentic_cli_flags_test.erl`
- Evidence（门禁）：
  - `rebar3 eunit --module=openagentic_cli_flags_test`（4 tests, 0 failures）

#### ✅ 差异点 21：Responses Provider store 默认行为（已完成）

- Kotlin 对齐点：
  - Responses payload 必带 `store`，默认 true；compaction pass 强制 `store=false`。
  - CLI 支持 `--openai-store/--no-openai-store`（影响 Responses 默认 store）。
- 落地：
  - `apps/openagentic_sdk/src/openagentic_openai_responses.erl`（store 默认与 payload 逻辑）
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`（将 `openai_store` 透传为 provider request `store`）
  - `apps/openagentic_sdk/src/openagentic_cli.erl`（`--openai-store/--no-openai-store`）
  - `apps/openagentic_sdk/test/openagentic_testing_provider_store.erl`
  - `apps/openagentic_sdk/test/openagentic_runtime_openai_store_test.erl`
  - `apps/openagentic_sdk/test/openagentic_openai_responses_test.erl`
- Evidence（门禁）：
  - `rebar3 eunit --module=openagentic_openai_responses_test --module=openagentic_runtime_openai_store_test`（3 tests, 0 failures）

#### ✅ 差异点 22：Responses Provider apiKeyHeader（已完成）

- Kotlin 对齐点：
  - provider 支持 `apiKeyHeader` 配置；当 header 为 `authorization` 时写 `Bearer <key>`，否则写 `<key>`。
- 落地：
  - `apps/openagentic_sdk/src/openagentic_openai_responses.erl`（`api_key_header` 解析 + headers 构建）
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`（将 `api_key_header` 透传给 provider request）
  - `apps/openagentic_sdk/test/openagentic_openai_responses_test.erl`（headers 构建门禁）
  - `apps/openagentic_sdk/test/openagentic_testing_provider_api_key_header.erl`
  - `apps/openagentic_sdk/test/openagentic_runtime_api_key_header_test.erl`
- Evidence（门禁）：
  - `rebar3 eunit --module=openagentic_openai_responses_test --module=openagentic_runtime_api_key_header_test`（5 tests, 0 failures）

#### ✅ 差异点 23：CLI `.env` + flags 覆盖面（已完成）

- Kotlin 对齐点：
  - 从 `--project-dir`（默认 cwd）读取 `.env`，并与进程 env 合并（`.env` 优先；flags 优先于 `.env`）。
  - flags 覆盖：`--api-key/--api-key-header/--openai-store/--no-openai-store/--project-dir(--cwd alias)`。
- 落地：
  - `apps/openagentic_sdk/src/openagentic_dotenv.erl`（`.env` 解析/加载）
  - `apps/openagentic_sdk/src/openagentic_cli.erl`（读取 `.env` + flags + 优先级）
  - `apps/openagentic_sdk/test/openagentic_dotenv_test.erl`
  - `apps/openagentic_sdk/test/openagentic_cli_dotenv_precedence_test.erl`
  - `apps/openagentic_sdk/test/openagentic_cli_flags_test.erl`（更新：使用临时 `--project-dir`，避免读取仓库根 `.env`）
- Evidence（门禁）：
  - `rebar3 eunit --module=openagentic_dotenv_test --module=openagentic_cli_dotenv_precedence_test --module=openagentic_cli_flags_test`（9 tests, 0 failures）

#### ✅ 差异点 24：Anthropic Messages provider（已完成）

- Kotlin 对齐点：
  - Anthropic Messages API：Responses-format input/tools 转换、non-stream & SSE streaming（含 tool_use / input_json_delta）。
  - 离线门禁必须覆盖 parsing/stream decoder（不打真实网络）。
- 落地：
  - `apps/openagentic_sdk/src/openagentic_anthropic_messages.erl`（provider；支持 `provider_mod` 注入）
  - `apps/openagentic_sdk/src/openagentic_anthropic_parsing.erl`（input/tools/content 转换）
  - `apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder.erl`（SSE 事件解码 + delta）
  - `apps/openagentic_sdk/test/openagentic_anthropic_parsing_test.erl`
  - `apps/openagentic_sdk/test/openagentic_anthropic_sse_decoder_test.erl`
- Evidence（门禁）：
  - `rebar3 eunit --module=openagentic_anthropic_parsing_test --module=openagentic_anthropic_sse_decoder_test`（3 tests, 0 failures）

#### ✅ 差异点 16：Built-in SubAgents（explore）（已完成）

- Kotlin 对齐点：
  - 内置 `explore` agent 定义（prompt marker + allowedTools = Read/List/Glob/Grep）
  - 默认 runner 组合：当 `task_agents` 含 `explore` 且未显式配置 `task_runner` 时，自动提供 `built_in_explore` runner
  - Task prompt 的 `{{agents}}` 占位符会被渲染为 `- <name>: <desc> (tools: ...)` 列表（与 Kotlin `TaskAgent.renderLine()` 一致）
- 落地：
  - `apps/openagentic_sdk/src/openagentic_built_in_subagents.erl`
  - `apps/openagentic_sdk/src/openagentic_task_agents.erl`
  - `apps/openagentic_sdk/src/openagentic_task_runners.erl`
  - `apps/openagentic_sdk/src/openagentic_tool_prompts.erl`（`code:priv_dir` 不可用时回退到 repo 内 `apps/openagentic_sdk/priv`，便于离线/手动 eunit）
  - `apps/openagentic_sdk/src/openagentic_tool_schemas.erl`（`agents` 注入）
- Evidence（门禁）：
  - `apps/openagentic_sdk/test/openagentic_task_agents_render_test.erl`

---

## 第四轮（2026-03-04）Runtime / Provider 语义对齐（进行中）

> 这一轮不再是“工具集合对齐”本身，而是对齐 Kotlin runtime/provider 的一些关键**行为语义**，否则模型/调用方会被细节差异误导。
> 本节先把差异点 + DoD 写清楚（作为本轮门禁清单），实现完成后再逐项打勾，并补上可复现实证（eunit 输出 / 关键文件）。

- [x] 17 PermissionMode 优先级（permissionModeOverride / sessionPermissionMode）
- [x] 18 runtime.error 的 ProviderException 分类（phase/error_type/error_message）
- [x] 19 SSE endOfInput flush + stream read timeout

### 第四轮总门禁（完成后记录）

- `rebar3 eunit`（84 tests, 0 failures）
- `.\scripts\kotlin-parity-check.ps1`（OK）

### 17) PermissionMode 优先级（permissionModeOverride / sessionPermissionMode）（中优先）

- Kotlin：effective gate mode 选择逻辑为：
  - `options.permissionModeOverride ?: options.sessionPermissionMode ?: options.permissionGate.mode`
  - 如果 mode 变了，会用 `gateForMode()` 构造新的 gate（并继承 userAnswerer）
- Erlang：此前只支持直接传 `permission_gate`（mode 固定），没有 override/session 两级。
- DoD：
  - runtime 支持：
    - `permission_mode_override` / `permissionModeOverride`
    - `session_permission_mode` / `sessionPermissionMode`
  - 优先级与 Kotlin 一致；override 生效时不要求调用方重新构造 gate。
  - 离线门禁：eunit 覆盖 “session 覆盖 gate”，“override 覆盖 session”。
- 状态（进行中）：
  - 已落地实现（已通过门禁）：
    - `apps/openagentic_sdk/src/openagentic_runtime.erl`：`effective_permission_gate/3`
    - `apps/openagentic_sdk/src/openagentic_permissions.erl`：新增 `prompt/0`（兼容无 user_answerer 的 gate 构造）
  - Evidence（通过门禁后补）：
    - `rebar3 eunit --module=openagentic_permission_mode_override_test`（3 tests, 0 failures）

### 18) runtime.error 的 ProviderException 分类（phase/error_type/error_message）（高优先）

- Kotlin：
  - `phase = if (t is ProviderException) "provider" else "session"`
  - `error_type = t::class.simpleName`（如 `ProviderRateLimitException` / `ProviderHttpException` / `ProviderTimeoutException` / `ProviderInvalidResponseException`）
  - `error_message = t.message`
- Erlang：此前只有粗粒度 `ProviderError/RuntimeError`，message 多为 `~p` 打印的 Reason。
- DoD：
  - `runtime.error` 的 `phase/error_type/error_message` 对齐 Kotlin 语义（允许 message 文案细微差异，但必须可归因）。
  - 离线门禁：eunit 用 mock provider reason 覆盖 429/stream ended/timeout 等。
- 状态（进行中）：
  - 已落地实现（已通过门禁）：
    - `apps/openagentic_sdk/src/openagentic_runtime.erl`：`provider_error_type/1`、`session_error_type/1`、`error_message/2`
    - 新增测试 provider：
      - `apps/openagentic_sdk/test/openagentic_testing_provider_http_429.erl`
      - `apps/openagentic_sdk/test/openagentic_testing_provider_stream_fail.erl`
      - `apps/openagentic_sdk/test/openagentic_testing_provider_missing_required.erl`
    - 新增门禁：
      - `apps/openagentic_sdk/test/openagentic_runtime_provider_error_semantics_test.erl`
  - Evidence（通过门禁后补）：
    - `rebar3 eunit --module=openagentic_runtime_provider_error_semantics_test`（3 tests, 0 failures）

### 19) SSE endOfInput flush + stream read timeout（中优先）

- Kotlin：`SseEventParser.endOfInput()` 会 flush buffer，并在输入结束时 finalize 当前 event（即使没有空行终止符）。
- Erlang：原 `openagentic_sse` 只有按 `\n\n` finalize，若对端在最后一次 chunk 未带空行，可能丢最后一个 event。
- DoD：
  - 增加 `end_of_input/1`，并在 provider 收到 `stream_end` 时 flush。
  - Streaming 读超时应该允许更长（Kotlin 默认 5 分钟），避免“长时间无 delta”被误判 timeout。
- 状态（已完成）：
  - 已落地实现（已通过门禁）：
    - `apps/openagentic_sdk/src/openagentic_sse.erl`：新增 `end_of_input/1`
    - `apps/openagentic_sdk/src/openagentic_openai_responses.erl`：`stream_end` 时调用 `end_of_input/1`；支持 `stream_read_timeout_ms`（默认 300000）
    - 新增 eunit：
      - `apps/openagentic_sdk/test/openagentic_sse_test.erl`：`end_of_input_flushes_pending_event_test/0`
  - Evidence（通过门禁后补）：
    - `rebar3 eunit --module=openagentic_sse_test`（2 tests, 0 failures）

### 20) CLI flags（compaction/max_steps/stream toggles）差异（中优先）

- Kotlin CLI（v4）：支持并使用以下行为/参数（参考 `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\cli\Main.kt`）：
  - streaming 默认开启（`--no-stream` 可关闭）
  - `--max-steps <n>`（1..200）
  - compaction 相关 flags：`--context-limit/--reserved/--input-limit`
- Erlang CLI：✅ 已对齐上述 flags（见 `openagentic_cli_flags_test` 门禁）。
- DoD：
  - `openagentic chat/run` 解析并透传：
    - `--no-stream`（默认 streaming=on，对齐 Kotlin）
    - `--max-steps <n>` → runtime `max_steps`
    - `--context-limit/--reserved/--input-limit` → runtime `compaction` map（keys 与 runtime 现有解析一致）
  - 门禁：新增 eunit 覆盖 CLI flags 解析与 opts 映射（避免只改 usage 文案）。

### 21) Responses Provider：`store` 默认行为（defaultStore/openai-store）差异（高优先）

- Kotlin（OpenAI Responses provider）：
  - 请求 payload 会**总是**带 `store` 字段：`store = request.store ?: defaultStore`（默认 `defaultStore=true`）。
  - compaction pass 会显式 `store=false`（避免把 compaction 产生的 response 写入 provider store）。
- Erlang（OpenAI Responses provider）：
  - 当前只有当 runtime 显式传入 `store` 时才写入 payload（否则不带 `store` 字段）。
  - runtime compaction pass 已强制 `store=false`（已对齐 Kotlin 的 compaction 行为）。
- 风险：真实 OpenAI 上，`previous_response_id` 的可用性与 provider store 行为强相关；不对齐会导致“看起来支持 resume，但线上不稳定/不可用”。
- DoD：
  - `openagentic_openai_responses` 的 request body 构建：当 `request.store` 未显式指定时，使用 `default_store`（默认 true），并且 **payload 必带 `store` 字段**。
  - runtime 支持配置默认 store（例如 `openai_store/openAiStore/default_store/defaultStore` 等任一稳定入口；并明确优先级），并在普通模型调用中向 provider 传递。
  - compaction pass 继续强制 `store=false`（保持现有）。
  - 门禁：离线 eunit 覆盖 payload 是否含 `store` + defaultStore 覆盖逻辑（不依赖真实网络）。

### 22) Responses Provider：`api_key_header` / `apiKeyHeader` 差异（中优先）

- Kotlin：
  - provider 支持 `apiKeyHeader` 配置；当 header 为 `authorization` 时会写 `Bearer <key>`，否则写 `<key>`（参考 `OpenAIResponsesHttpProvider` 的 header 构建逻辑）。
- Erlang：
  - 当前固定使用 `authorization: Bearer <key>`。
- DoD：
  - `openagentic_openai_responses` 支持可配置 `api_key_header`（含 `apiKeyHeader` 别名），并实现 Kotlin 一致的 header 写法（authorization=Bearer，其余为 raw key）。
  - 门禁：离线 eunit 验证 headers 构建（authorization vs custom header）。

### 23) CLI：`.env` 读取 + flags 覆盖面差异（中优先）

- Kotlin CLI：
  - 从 `--project-dir`（默认 cwd）读取 `.env`，并与进程 env 合并（`.env` 优先）。
  - flags 覆盖：`--api-key/--api-key-header/--openai-store/--no-openai-store/--project-dir(--cwd alias)` 等。
- Erlang CLI：
  - 当前主要依赖 env（`OPENAI_API_KEY/OPENAI_MODEL/OPENAI_BASE_URL`），flags 覆盖面不足。
- DoD：
  - `openagentic` CLI 增加 `.env` 读取（按 Kotlin 兼容：支持引号、忽略空行/注释、key=value），并实现 Kotlin 同等优先级（`.env` > env）。
  - 增加 flags（至少）：
    - `--project-dir <dir>`（`--cwd` 作为 legacy alias）
    - `--api-key <key>`（优先级最高）
    - `--api-key-header <header>`
    - `--openai-store <bool>` 与 `--no-openai-store`（影响 Responses provider 的 defaultStore）
  - 门禁：eunit 覆盖 `.env` 解析与“flags/.env/env”优先级（不读用户真实 `.env`，用临时文件夹夹具）。

### 24) Provider 扩展：Anthropic Messages（可选；Kotlin 已有）（高工作量）

> 说明：此项不属于“OpenAI tool/runtime parity”的最小闭环，但 Kotlin repo 已包含该 provider；若目标是“功能面完全一致”，需纳入。

- Kotlin：提供 `AnthropicMessagesHttpProvider`（complete + streaming）以及对应 parsing/decoder/异常语义。
- Erlang：尚无对应 provider。
- DoD：
  - 增加 Erlang provider（实现 `openagentic_provider` 行为）并可通过 `provider_mod` 注入运行。
  - 完成“最小可用”与错误语义对齐：timeout/http>=400/invalid JSON 等映射到 Kotlin 风格 `runtime.error` 归因。
  - 门禁：离线 fixtures 覆盖 parsing/streaming decoder（不打真实网络）。

### 本轮实现中的已知失败（待修复后再勾选）

> 记录到这里是为了防止我 compact context 后忘掉“当前卡住点”，并保证后续修复也能回写 Evidence。

- eunit 当前失败（2026-03-04）：无
- 已修复（记录一下避免重复踩坑）：
  - `openagentic_permission_mode_override_test:*`：原因是测试未 reset `openagentic_test_step`，导致 provider 不产出 tool call；已在测试里统一 `erlang:erase(openagentic_test_step)`
  - `openagentic_runtime_resume_test:*`：同样需要 reset `openagentic_test_step`，否则会把 resume 的 `previous_response_id` 断言搞乱
