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
