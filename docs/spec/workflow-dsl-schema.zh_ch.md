# OpenAgentic Workflow DSL Schema（v1）

> 中文版（偏“严格字段定义 + 校验规则”）。英文规范版见：`docs/spec/workflow-dsl-schema.md`。
>
> 本文档是后续实现 `workflow_engine` 的验收基线，并服务于：
> - `docs/spec/workflow-engine.md`
> - `docs/spec/workflow-engine.zh_ch.md`

## 1. 目标

- 定义一套 **可机检** 的 workflow DSL，让流程“不可跳步”。
- 数据模型足够简单，未来才可能跨语言复用（但 v1 不强求跨语言实现）。
- DSL 校验 **fail-fast**：配置错就直接拒绝启动，避免静默跑歪。

## 2. 文件格式与加载规则

- 规范序列化：**JSON（UTF-8）**
- 可选序列化：YAML（同 schema），但 v1 可以只支持 JSON
- 典型路径：
  - `workflows/<name>.json`
- prompt 模板文件（可选）：
  - `workflows/prompts/<step_id>.md`

安全约束：
- prompt 只是文本，不执行
- 不读取/不打印任何密钥（例如 `.env`）

## 3. 版本

- `workflow_version`：v1 固定为 `"1.0"`
- 不认识的版本必须拒绝加载
- v1 推荐：出现未知字段就拒绝（防止“看起来能跑，实际上语义丢了”）

## 4. 顶层对象（workflow）

必填字段：
- `workflow_version`（string，必须 `"1.0"`）
- `name`（string，稳定标识）
- `steps`（Step[]，至少 1 个）

可选字段：
- `description`（string）
- `roles`（map：`role_name -> RoleSpec`）
- `defaults`（Defaults）

### 4.1 RoleSpec

```json
{ "purpose": "简短说明" }
```

v1 仅作为信息字段（以后可用于拼系统提示词/审计显示）。

### 4.2 Defaults

```json
{
  "max_attempts": 3,
  "timeout_seconds": 900,
  "tool_policy": { ... }
}
```

对所有 step 生效，step 可覆盖。

## 5. Step 对象

必填字段：
- `id`（string；workflow 内唯一；建议 `[a-z0-9_]+`）
- `role`（string；如果提供了 `roles`，建议必须在其中）
- `input`（InputBinding）
- `prompt`（PromptRef）
- `output_contract`（OutputContract）
- `on_pass`（string step id 或 `null` 表示终止）
- `on_fail`（string step id 或 `null` 表示失败终止）

可选字段：
- `guards`（Guard[]，默认 `[]`）
- `max_attempts`（int >= 1，默认取 `defaults`）
- `timeout_seconds`（int >= 1，默认取 `defaults`）
- `tool_policy`（ToolPolicy，默认取 `defaults`）
- `executor`（string；v1 若出现必须是 `"local_otp"`；保留 `"http_sse_remote"` 作为未来值）

校验规则（加载时做）：
- step `id` 全部唯一
- `on_pass/on_fail` 引用的 step 必须存在
- 至少存在一条可达的终止路径（`on_pass=null` 或 `on_fail=null`）
- 未知 `executor` 必须拒绝

## 6. InputBinding（输入绑定）

用 `type` 区分的 union：

### 6.1 `controller_input`

```json
{ "type": "controller_input" }
```

workflow 启动时传入的输入。

### 6.2 `step_output`

```json
{ "type": "step_output", "step_id": "draft_plan" }
```

绑定到该 step 最近一次“通过”的产物。

### 6.3 `merge`

```json
{
  "type": "merge",
  "sources": [
    { "type": "step_output", "step_id": "a" },
    { "type": "step_output", "step_id": "b" }
  ]
}
```

合并策略（建议 v1 先简单）：
- 默认：按顺序拼接文本（带分隔符）
- 如果显式要求 JSON：再做对象 merge（后者覆盖前者）

### 6.4 保留类型（未来）

允许在 schema 中出现但 v1 可以拒绝：
- `artifact_ref`
- `event_query`

## 7. PromptRef（提示词引用）

### 7.1 `inline`

```json
{ "type": "inline", "text": "..." }
```

### 7.2 `file`

```json
{ "type": "file", "path": "workflows/prompts/draft_plan.md" }
```

校验建议：
- v1 默认：`file.path` 必须存在，否则拒绝加载

## 8. OutputContract（产物契约）

### 8.1 `markdown_sections`

```json
{ "type": "markdown_sections", "required": ["目标","计划"] }
```

规则：输出必须包含所有 required 标题段（例如匹配 `^#+\\s+标题`）。

### 8.2 `decision`

```json
{
  "type": "decision",
  "allowed": ["approve","reject"],
  "format": "json",
  "fields": ["decision","reasons","required_changes"]
}
```

规则：必须是 JSON 对象，包含 fields，并且 decision 在 allowed 内。

### 8.3 `json_object`

```json
{ "type": "json_object", "schema_hint": { "tasks": [] } }
```

规则：能解析成 JSON 对象。`schema_hint` 仅用于引导/提示，不是强校验。

### 8.4 保留类型（未来）

- `json_schema`（真正的 JSON Schema 校验）
- `artifact_required`（强制产出 artifact 引用）

## 9. Guard（硬门槛）

Guard 是引擎在产物生成后执行的确定性校验。

### 9.1 `max_words`

```json
{ "type": "max_words", "value": 900 }
```

### 9.2 `regex_must_match`

```json
{ "type": "regex_must_match", "pattern": "\"tasks\"\\s*:" }
```

### 9.3 `markdown_sections`

```json
{ "type": "markdown_sections", "required": ["DoD"] }
```

### 9.4 `decision_requires_reasons`

```json
{ "type": "decision_requires_reasons", "when": "reject" }
```

规则：当 decision 为 reject 时，`reasons` 与 `required_changes` 必须是非空数组。

### 9.5 `requires_evidence`

```json
{ "type": "requires_evidence", "commands": ["rebar3 eunit"] }
```

规则：事件日志里必须能证明这些命令确实被执行过（证据如何表示由实现决定，但必须可验证）。

v1 强制规则：
- 未知 guard `type`：加载时直接拒绝（fail-fast）

## 10. ToolPolicy（工具权限策略）

```json
{
  "mode": "default",
  "allow": ["Read", "Grep"],
  "deny": ["Bash"]
}
```

字段：
- `mode`：`default | prompt | deny | bypass`
- `allow/deny`：对工具名的增量控制

合并规则（建议）：
- 先取 runtime 默认策略
- 叠加 workflow defaults
- step 级覆盖

安全提示：
- `bypass` 权限很大，只应在可信环境启用。

## 11. 示例

参考 fixture：

- `workflows/three-provinces-six-ministries.v1.json`

