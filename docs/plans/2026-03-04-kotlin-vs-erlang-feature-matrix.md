# Kotlin ↔ Erlang 功能点对照表（宏观视图）

> Snapshot date: **2026-03-04**  
> 目标：把 `openagentic-sdk-kotlin` 的“功能面”按模块分层列出来，对照 `openagentic-sdk-erlang` 的实现与差异，方便快速判断还差多少、差在哪里。

## 读法

- **Kotlin**：以 `openagentic-sdk-kotlin` 当前代码为准（文件路径仅作定位）。
- **Erlang**：以本仓库当前实现为准（文件路径仅作定位）。
- **状态**：
  - ✅ 已对齐/等价实现（允许实现细节不同，但语义一致）
  - ⚠️ 部分对齐（存在影响体验/行为的差异）
  - ❌ 缺失（Kotlin 有、Erlang 暂无）
- **是否纳入对齐范围**：以柠檬叔当下要求为准；例如 LSP 的 Kotlin 扩展能力此前已明确不需要完全对齐。

---

## 一句话结论（宏观）

- **工具层（toolprompts / schemas / safe-tools / default-tools / tool-loop 基本语义）**：基本 ✅
- **当前主要差异集中在三类**：
  1) **CLI 配置体验**（Kotlin CLI 读 `.env`、更多 flags；Erlang CLI 以 env 为主）
  2) **Responses Provider 的 store 默认行为 + apiKeyHeader 可配置**（会影响 `previous_response_id` 在真实 OpenAI 上是否可用）
  3) **Kotlin 额外 providers（如 Anthropic）与更完整 LSP 生态**（若纳入范围才算差异）

---

## 功能点矩阵

| 领域 | Kotlin（功能点 / 入口） | Erlang（对应实现 / 状态） | 差异/备注 |
|---|---|---|---|
| ToolPrompts 资源 | `src/main/resources/.../toolprompts/*.txt` | ✅ `apps/openagentic_sdk/priv/toolprompts/*.txt` | 文件列表/大小已对齐（见仓库内文件） |
| ToolPrompts 注入 | `OpenAiToolSchemas.kt` 注入 ToolPrompts（如 question/read/list/...） | ✅ `apps/openagentic_sdk/src/openagentic_tool_schemas.erl` | 变量替换策略按 parity 门禁对齐 |
| Tool Schemas（工具清单） | schemasByName 覆盖：AskUserQuestion/Read/List/Write/Edit/Glob/Grep/Bash/WebFetch/WebSearch/SlashCommand/Skill/NotebookEdit/lsp/Task/TodoWrite | ✅ runtime 默认注册覆盖：`apps/openagentic_sdk/src/openagentic_runtime.erl`（`default_tools/0`） | Kotlin tools 列表与 Erlang default_tools 已对齐（tool 级别） |
| PermissionGate safe-tools | DEFAULT safe：`Read/Glob/Grep/Skill/SlashCommand/AskUserQuestion` | ✅ `apps/openagentic_sdk/src/openagentic_permissions.erl`（`safe_tools/0`） | safe-tools 集合一致 |
| Sessions（meta+events.jsonl） | `FileSessionStore`：`meta.json` + `events.jsonl` 追加写 | ✅ `apps/openagentic_sdk/src/openagentic_session_store.erl` | 结构一致（meta + jsonl） |
| Sessions Resume | `resumeSessionId` + resumeMaxEvents/Bytes | ✅ `apps/openagentic_sdk/src/openagentic_runtime.erl`（`resume_session_id` + 限流） | 语义已按 parity 落地 |
| Provider Retry/Backoff | `ProviderRetryOptions`（Retry-After + backoff） | ✅ `apps/openagentic_sdk/src/openagentic_provider_retry.erl` | 语义已按 parity 落地 |
| Streaming / SSE idle timeout | provider streamReadTimeoutMs=5min（避免无 delta 误超时） | ✅ `apps/openagentic_sdk/src/openagentic_openai_responses.erl`（默认 300000ms） | 行为等价（单位/实现不同） |
| Hooks | `HookEngine`（pre/post tool hooks） | ✅ `apps/openagentic_sdk/src/openagentic_hook_engine.erl` + runtime 接入 | 语义已对齐 |
| Tool output artifacts | `ToolOutputArtifactsOptions`（输出过大外置文件） | ✅ runtime 支持 `tool_output_artifacts` | 语义已对齐 |
| Compaction（overflow+pruning+summary pivot） | `Compaction.kt`（overflow 判定、prune、summary pivot） | ✅ `apps/openagentic_sdk/src/openagentic_compaction.erl` + runtime 触发 | 语义已按 parity 落地 |
| Task/SubAgents（explore） | `BuiltInSubAgents.kt` / `TaskRunners.kt` | ✅ `apps/openagentic_sdk/src/openagentic_built_in_subagents.erl` / `openagentic_task_runners.erl` 等 | 已按 parity 落地（explore agent + 默认 runner） |
| LSP 生态（完整能力） | Kotlin 有 manager/registry + stdio client + registry/root resolver 等 | ⚠️ Erlang 仅最小可用 tool：`apps/openagentic_sdk/src/openagentic_tool_lsp.erl` | **已明确不要求完全对齐 Kotlin 扩展能力**（若未来改主意再纳入） |
| Providers（OpenAI Responses） | `OpenAIResponsesHttpProvider`（`apiKeyHeader`、`defaultStore=true`） | ⚠️ `apps/openagentic_sdk/src/openagentic_openai_responses.erl`（SSE via httpc） | 主要差异见下两行：store 默认、apiKeyHeader |
| Responses: store 默认行为 | Kotlin：请求会写 `store = request.store ?: defaultStore(true)`（默认 true） | ⚠️ Erlang：只在显式传入 `store` 时才写入 payload（compaction pass 强制 `store=false`） | **高影响差异**：可能影响 `previous_response_id` 的真实可用性与跨轮能力 |
| Responses: apiKeyHeader 可配置 | Kotlin：`apiKeyHeader` 可配（authorization 时自动 Bearer） | ❌ Erlang：固定 `authorization: Bearer <key>` | 若要兼容非标准网关/代理，需要补齐 |
| Providers（OpenAI Chat Completions / legacy） | Kotlin：`OpenAIChatCompletionsHttpProvider` | ✅ Erlang：`apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl` | 已落地 |
| Providers（Anthropic 等） | Kotlin：providers 包含 Anthropic Messages 等 | ❌ Erlang：未实现 | 是否纳入对齐范围取决于目标（当前可视为“范围外差异”） |
| CLI（配置来源） | Kotlin CLI：读取 projectDir 下 `.env` + env | ❌ Erlang CLI：仅 env（`OPENAI_API_KEY/OPENAI_MODEL/...`） | 若追求 CLI 体验对齐，可补 `.env` 解析 |
| CLI（flags 覆盖） | Kotlin CLI：`--api-key/--api-key-header/--openai-store/--project-dir/...` | ⚠️ Erlang CLI：已有 `--protocol/--model/--base-url/--resume/--permission/--(no-)stream/--max-steps/--context-limit/--reserved/--input-limit` | 仍缺 `--api-key/--api-key-header/--openai-store/--project-dir` 等 |

---

## 建议的“下一步对齐”（如果要继续做宏观差异）

按影响优先级（不代表必须做）：

1. **Responses provider：`store` 默认行为对齐 Kotlin**（默认 true）+ CLI/opts 可显式 override
2. **Responses provider：支持 `api_key_header` / `apiKeyHeader`**
3. **Erlang CLI：读取 `.env`（与 Kotlin CLI 一致）** + 增补 `--api-key/--project-dir` 等
4. （可选/范围外）Anthropic provider

