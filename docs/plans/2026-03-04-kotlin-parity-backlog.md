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

## 执行记录（防 compact 丢清单）

### 2026-03-04（本轮累计进展）

> NOTE（环境）：当前 Windows 环境下 `erl:open_port({spawn,...})` 返回 `einval`，导致 `rebar3` 的依赖/编译阶段无法稳定运行（需要进一步排查 OTP/系统策略）。本轮新增门禁已用“手工 `erlc` 编译 + `eunit:test(...)`”方式验证通过，避免被环境问题卡死。

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
