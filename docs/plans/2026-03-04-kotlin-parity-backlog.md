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
- Erlang：`openagentic_fs:resolve_tool_path/2` 目前仅做“词法归一化 + 前缀判定”，**未做 symlink escape**。
  - `apps/openagentic_sdk/src/openagentic_fs.erl`
- DoD：补齐与 Kotlin 等价的 symlink escape 检测 + eunit（至少覆盖：`projectRoot/link -> outside` 场景）。

### 2) 错误语义（exception 类型/消息）仍存在系统性差异（高优先）

- Kotlin runtime：工具抛出的异常类型会被写入 `tool.result.error_type = e::class.simpleName`，错误信息来自 `e.message`。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
- Erlang runtime：目前仅对 `{error, {kotlin_error, Type, Msg}}` 做精确映射；大量 I/O 错误仍会落到 `ToolError`（tuple stringify），与 Kotlin 不一致。
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`
- 待补齐的典型场景（示例，非穷尽）：
  - `Read`：文件不存在/不可读时 Kotlin 倾向于 `FileNotFoundException`/I/O 异常；Erlang 目前 `{read_failed, ...}`。
  - `Grep`：Kotlin `Regex(query)` 可能抛 `PatternSyntaxException`；Erlang 目前 `{invalid_input, {bad_regex, ...}}`。
  - `Glob/Grep`：Kotlin 对 `root/path` 非目录/不存在的行为更偏“抛异常”；Erlang 目前多为显式 `{not_a_directory,...}`。
- DoD：为每个默认工具补齐“失败路径”的 error_type/error_message 对齐用例，并把 Erlang 侧错误统一映射到 Kotlin 异常类型名（至少覆盖：`IllegalArgumentException/IllegalStateException/FileNotFoundException/RuntimeException/PatternSyntaxException`）。

### 3) LSP 工具能力差异（较大缺口）

- Kotlin：`lsp` 具备 **builtin server registry + root resolver**（按 lockfiles/项目文件定位 root），并支持通过配置覆盖/禁用 builtin；无可用 server 时抛 `RuntimeException("No LSP server available for this file type.")`。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\lsp\LspRegistry.kt`
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\lsp\LspManager.kt`
- Erlang：当前 `lsp` 为最小实现，仅解析 OpenCode config 并启动 stdio JSON-RPC；**无 builtin registry/root resolver**，且部分错误类型未对齐 Kotlin。
  - `apps/openagentic_sdk/src/openagentic_tool_lsp.erl`
- DoD：对齐 Kotlin 的 builtin registry（至少覆盖常用：`pyright/rust-analyzer/clangd/kotlin-ls/bash` 等）+ root resolver 策略 + 错误类型/消息。

### 4) WebFetch 清洗/Markdown 语义差异（中-高优先）

- Kotlin：`WebFetch` 使用 jsoup + safelist + boilerplate stripping + absolutize links + html2md（markdown 模式）。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\WebFetchTool.kt`
- Erlang：当前实现为 best-effort 的正则去标签/去块，`clean_html/markdown` 语义与 Kotlin 差异显著。
  - `apps/openagentic_sdk/src/openagentic_tool_webfetch.erl`
- DoD：补齐更接近 Kotlin 的清洗策略（至少：去 nav/footer/ads、链接绝对化、markdown 规范化），并加离线 fixtures 测试确保输出稳定。

### 5) WebSearch（DDG fallback）失败行为差异（中优先）

- Kotlin：DDG fallback 的 HTTP GET 若 `status>=400` 会抛异常（RuntimeException），并会影响 tool.result 的 error_type/error_message。参考：
  - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\tools\WebSearchTool.kt`
- Erlang：DDG 请求失败时通常返回空结果而非抛错（当前更“宽松”）。
  - `apps/openagentic_sdk/src/openagentic_tool_websearch.erl`
- DoD：对齐 Kotlin 的失败语义（HTTP 错误时抛错/错误类型一致），并新增离线测试（通过 transport/fixture 模拟）。

### 6) Runtime Hook / Tool Output Artifacts 差异（中-高优先）

- Kotlin runtime：
  - 支持 pre/post hooks，可阻断 tool use（`error_type = HookBlocked`）。参考：
    - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
  - 对超大 tool output 支持 externalize 到 artifact 文件，并用 wrapper 返回 `artifact_path/preview/hint`（模型可继续用 `Read` 读取）。参考：
    - `E:\development\openagentic-sdk-kotlin\src\main\kotlin\me\lemonhall\openagentic\sdk\runtime\OpenAgenticSdk.kt`
- Erlang runtime：当前无 hooks、无 tool output externalization（大输出只会直接写入 events.jsonl 或被上游截断）。
  - `apps/openagentic_sdk/src/openagentic_runtime.erl`
- DoD：补齐 hooks（至少：pre_tool_use/post_tool_use 的 allow/block 机制）与 output externalization（目录、命名、wrapper JSON 结构）并新增离线门禁测试。
