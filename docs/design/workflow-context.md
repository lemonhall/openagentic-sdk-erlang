# Workflow 上下文与会话模型（`workflow_session_id` vs `step_session_id`）

本文档说明 `openagentic-sdk-erlang` 当前的 workflow 运行时是如何管理 **session / history / 上下文拼装** 的，避免“看起来像同一局聊天，但实际上每一步都是独立调用”的误解。

适用版本：2026-03-06（以仓库当前实现为准）

---

## TL;DR（结论先行）

- 一个 workflow 的**主会话**是 `workflow_session_id`：负责 **事件落盘、SSE 可观测、Continue 追记**、以及承载本 workflow 的 `workspace/`。
- 每个 step（太子/中书/门下/尚书/六部…）在执行时会创建一个独立的 **分会话**：`step_session_id`，用于该 step 的一次 LLM/tool-loop 运行（并可在 tool-loop 内 resume）。
- **不会**把主会话的 `events.jsonl` “整本历史”一次性喂给后续 LLM。
- 后续 step 能看到“皇帝原文”的原因不是因为它能读主会话历史，而是引擎每次调用都会把 `# Controller`（皇帝圣旨 + followups）**显式拼进当次 prompt**。

---

## 名词表

- **Workflow（流程）**：一份 DSL（如 `workflows/three-provinces-six-ministries.v1.json`）描述的多 step 有向图。
- **主会话（workflow session）**：`workflow_session_id`，对应目录 `.../sessions/<workflow_session_id>/`。
- **分会话（step session）**：`step_session_id`，对应目录 `.../sessions/<step_session_id>/`。
- **Attempt（尝试次数）**：同一个 step 在一次 run 中第几次执行（比如门下省 reject 后回到中书省，下一次再审就是 attempt+1）。
- **Run（一次运行）**：一次 start 或 continue 触发的一次“从某个 start_step_id 开始向后跑”的执行过程。

---

## 文件落盘布局（目录结构）

默认 session 根目录由 `OPENAGENTIC_SDK_HOME` 决定（Windows 环境一般是 `E:\openagentic-sdk`）。

主会话目录：

```
E:\openagentic-sdk\sessions\<workflow_session_id>\
  meta.json
  events.jsonl
  workspace\
    ...（允许写入的工作区内容：deliverables/ 等）
```

分会话目录（每个 step 一次执行会创建一个）：

```
E:\openagentic-sdk\sessions\<step_session_id>\
  meta.json            # workflow_id/step_id/role/attempt 等
  events.jsonl         # 该 step 内的完整 tool-loop 与 assistant 输出事件
  workspace\           # 当前实现里会创建，但一般不用于 workflow 主产物
```

> 重点：workflow 的“文书交付物”通常写入 **主会话的 workspace**（`workflow_session_id/workspace/...`）。

---

## 关键关系（ASCII 图）

### 1) “一个 workflow = 一个主会话 + 多个分会话”

```
workflow_session_id (主会话)
│
├─ events.jsonl    # workflow 全链路可观测事件（SSE 就是读它）
├─ workspace/      # 该 workflow 的工作区（deliverables 等）
│
└─ step_session_id (分会话，多个)
   ├─ events.jsonl # 某一步的 tool-loop 原始事件
   └─ meta.json    # step_id / role / attempt / workflow_id
```

### 2) “UI 看到的 step 事件从哪来”

```
step_session 的事件（tool.use/tool.result/assistant.delta/…）
   │
   │  Bridge（桥接）
   ▼
workflow_session 的 workflow.step.event（携带 step_session_id）
   │
   ▼
Web UI SSE：/api/sessions/<workflow_session_id>/events
```

---

## LLM 看到的上下文是什么？

每个 step 执行时，引擎会构造一段 `UserPrompt`，结构固定（分隔符 ASCII-only）：

```
<Step Prompt（该角色/该 step 的提示词）>

---
# Controller
<皇帝最初圣旨 + 所有 Continue Followup 追加>

---
# Input
<本 step 的输入绑定（通常来自上一步输出或 merge）>

---
# Previous failure reasons (must fix)   （可选，仅当该 step 之前 guard 失败过）
- ...
```

要点：

- **皇帝原文**总是出现在 `# Controller`，所以六部不会“只能看尚书转述”。
- 六部是否能看到其他部门报告，取决于 DSL 是否把那些 step_output merge 到它的 `# Input`；默认六部只拿尚书分派单（`shangshu_dispatch`）作为 `# Input`。
- “主会话 events.jsonl 全量历史”不会被自动塞进 prompt；主会话更多是可观测与持久化容器。

实现位置（便于读代码）：

- prompt 拼装：`apps/openagentic_sdk/src/openagentic_workflow_engine.erl`（`build_user_prompt/5`）
- `# Input` 绑定：同文件（`bind_input/2`，支持 `controller_input | step_output | merge`）

---

## 尚书分派与六部历史到底在哪里？

### 尚书分派（`shangshu_dispatch`）

- 这是 workflow 的一个 step：它的输出会写入 **主会话**的 `workflow.step.output(step_id=shangshu_dispatch)`。
- 同时，尚书 step 运行过程中的 tool 事件会被桥接回主会话（`workflow.step.event`），并且在尚书自己的 `step_session_id` 下也有完整 events。

### 六部（`hubu_data/libu_docs/...`）

每个部都是一个独立 step：

- 主会话：会看到该部的 `workflow.step.start / workflow.step.event / workflow.step.output`（足够 UI 展示与最终汇总）。
- 分会话：`E:\openagentic-sdk\sessions\<该部 step_session_id>\events.jsonl` 里会有该部更完整的 tool-loop 细节。

> 你如果要“追溯某部到底 search 了什么、fetch 了什么”，应优先看该部 `step_session_id` 的 events（最原始），其次看主会话里桥接后的 `workflow.step.event`（UI 友好但可能裁剪）。

---

## Continue / 多轮运行（Run）的语义

### Continue 做了什么？

- Web `continue` 会把你的新输入写入主会话：`workflow.controller.message`
- 引擎在下一次 run 的 `# Controller` 中，把：
  - 初始 controller_input（第一次圣旨）
  - 历史 followups（之前 continue 的消息）
  - 本次消息
  按固定格式拼接在一起（见 `# Followup` 段落）

因此：

- 同一个 `workflow_session_id` 可以有多次 run（start/continue 多次），但它们都是追加写 events。
- “新开一局”才会生成新的 `workflow_session_id`（相当于清空上下文并创建新的 workspace）。

---

## “独立对话”到底独立到什么程度？

可以理解为：

- **step 之间是“输入显式绑定”的弱耦合**：默认只通过 DSL 指定的 `# Input` 串联（比如 `step_output(shangshu_dispatch)`）。
- **step 内 tool-loop 是强耦合**：一次 step 运行期间，多次 tool call 来回依赖同一个 provider 会话（`previous_response_id` 或 compaction 兜底），并写入同一个 `step_session_id`。
- **attempt 重试不是同一个 step_session**：同一个 step 的 attempt+1 会创建新的 `step_session_id`；为了让模型能自纠，工作流引擎会把“上次失败原因”作为 `# Previous failure reasons` 注入到下一次 attempt 的 prompt（属于 workflow 引擎层的“纠错提示”，不是模型自动记忆）。

---

## 设计取舍（为什么这样做）

- **可控性**：每个部门/step 的可见上下文是可设计的（靠 DSL 的 `input` 绑定），避免“部门 A 莫名读到了部门 B 的草稿与隐私内容”。
- **可观测性**：主会话 events 是 UI 的唯一订阅源；分会话保留可追溯的原始细节（便于调试“工具到底怎么用的”）。
- **可恢复性**：分会话使得 step 内 tool-loop 可以依赖 provider 的恢复机制（`previous_response_id`）而不必把全部历史文本化重放。

---

## 常见误解澄清

1) “所有部门都在同一套聊天历史里自由交流”  
不是。部门之间默认只通过 DSL 明确的 `# Input` 传递。

2) “六部看不到皇帝原文，只能看尚书转述”  
不是。所有 step 的 `# Controller` 都包含皇帝原文（以及 followups）。

3) “主会话 events.jsonl 会被塞进 LLM”  
当前不会。喂给 LLM 的是当次拼装的 `UserPrompt`。

---

## 后续可改进点（留档）

- 将“哪些 step 能看到哪些 step_output”做成更显式的 DSL 约束/可视化（减少误配）。
- 对 UI 增加“查看某 step_session 的原始事件”入口（从主会话的 `step_session_id` 跳转）。
- attempt 重试可选“复用同一个 step_session”（让模型真的看到自己上次输出），但这会引入更强的跨 attempt 记忆，需谨慎权衡可控性与成功率。

