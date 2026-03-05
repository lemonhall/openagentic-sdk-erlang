# OpenAgentic 本地控制面 + 硬流程引擎（DSL 优先）

> 中文说明版（偏“来龙去脉 + 取舍”）。英文规范版见：`docs/spec/workflow-engine.md`。
>
> 相关（未来实现，v1 不依赖）：远程 subagent 协议（HTTP+SSE）已留档：
> - `docs/spec/agent-host-protocol.md`
> - `docs/spec/agent-host-protocol.zh_ch.md`

## 1. 你真正缺的两块是什么？

你现在的判断非常准确：

1) **控制面**：启停、监控、恢复、取消、状态可观测。
2) **硬性的 flow 引擎**：A 必须先跑，产物必须交给 B 审，没过就驳回返工；某些步骤不允许 AI 跳过。

我们已经有 “agent runtime/tool-loop + session 可 resume”。缺的就是把它们组织成一个 **不可跳步**、**可恢复**、**可审计** 的系统。

DSL schema 参考（后续实现的验收基线）：
- `docs/spec/workflow-dsl-schema.md`
- `docs/spec/workflow-dsl-schema.zh_ch.md`

## 2. 核心原则（把权力收回来）

- **流程引擎拥有调度权**：下一步跑谁、输入是什么、怎么转移状态，全部由引擎决定。
- **agent 只是执行器**：它负责生成某一步的产物，但不能决定“流程走到哪”。
- **session/event log 是事实来源**：进程挂了只是执行器挂了，不是状态丢了。
- **硬门槛（guards）**：通过/驳回必须由可检查的规则决定，而不是“模型说过了就算”。
- **证据链**：每一步要写入事件（或 artifact 引用），方便回放与审计。

这套原则一旦成立，“三省六部制”其实就是一个固定的状态机 + 规则集合。

## 3. 本地控制面（OTP 版）

### 3.1 一棵 workflow 的监督树（推荐）

对每个 workflow 实例：

- `workflow_instance_sup`（supervisor）
  - `workflow_engine`（`gen_statem`）：流程状态机（硬推进）
  - `agent_pool_sup`（supervisor）：管理本 workflow 需要的多个角色 agent
    - `role_agent`（`gen_server` / `gen_statem`）：调用现有 runtime 跑某一步

全局再有一个 `workflow_manager`（单机一个）：

- 管理并发、创建/恢复实例、提供状态查询

### 3.2 控制面能力（最小集）

- `start(workflow_name, input, opts) -> workflow_id`
- `status(workflow_id) -> 当前状态/当前 step/最近事件 seq`
- `cancel(workflow_id, reason)`
- `resume(workflow_id)`（崩溃后/重启后继续）

这就是你要的“启停、监控”基本盘；先把本地做扎实，再谈跨机。

### 3.3 崩溃恢复（为什么能成立）

成立的关键是：**状态写在 session/event log 里**。

- `workflow_engine` 重启后从 events 回放到最后一步
- `role_agent` 重启后也能从 session resume 上下文
- 幂等性：对有副作用的工具调用必须去重（例如用 tool_use_id/step_run_id 做幂等门闩）

## 4. 工作流事件模型（写入同一个 events.jsonl）

我们建议直接复用现有 `events.jsonl`，新增 workflow 相关事件类型：

- `workflow.init`：workflow 启动（workflow_id/workflow_name/DSL hash/输入摘要）
- `workflow.step.start`：某 step 开始（step_id/role/attempt）
- `workflow.step.output`：产物（或 artifact 引用）
- `workflow.guard.fail`：guard 失败（原因列表）
- `workflow.step.pass`：通过
- `workflow.transition`：状态迁移（from/to）
- `workflow.cancelled`：取消
- `workflow.done`：结束（最终产物引用）

原则：只要这些事件足够，**流程就能被回放重建**。

## 5. DSL（为什么要 DSL-first）

你说“肯定写成 DSL 更好”，核心好处是：

- 改流程不必改代码（把制度外置为文件）
- 不同语言实现可以共用同一份流程定义（以后要跨语言再说）
- “显式优于隐式”：制度清晰可审计

### 5.1 文件格式建议

为了跨语言与实现成本：

- 规范数据模型用 **JSON** 表达（最通用）
- 允许用 **YAML** 做等价序列化（更好读），但 v1 实现可以先只支持 JSON

推荐路径：

- `workflows/<name>.json`（或 `.yaml`）
- `workflows/prompts/<step_id>.md`（可选）

### 5.2 Step 的本质字段（硬约束）

每一步要明确：

- `role`：谁执行
- `prompt`：要干什么（inline 或引用文件）
- `input`：输入从哪里绑定（controller input / 前一步产物 / 事件选择 / artifact）
- `output_contract`：产物必须满足什么结构（硬性）
- `guards`：可机检规则（通过/驳回依据）
- `on_pass/on_fail`：通过/失败后的明确跳转（不能靠模型自由发挥）

### 5.3 Guard（v1 最小集合）

必须是确定性的、无需模型参与的校验：

- `markdown_sections(required=[...])`：必须包含指定标题段
- `regex_must_match(pattern=...)`
- `max_words(value=...)`
- `requires_evidence(commands=[...])`：声明“必须出现哪些证据”（例如 verify step 必须记录 `rebar3 eunit` 结果）

注意：`requires_evidence` 本身不负责运行命令，它负责“证据必须出现”，运行命令属于某个 step 的职责。

### 5.4 工具权限（按 role/step 施策）

“不容 AI 跳过”之外，另一个硬约束是“不能乱用工具”：

- 默认：只读工具直接放行
- 实施：仅在明确声明时允许 `Write/Edit`
- 验证：仅在明确声明时允许 shell/任务运行

这可以在 DSL 里定义 `tool_policy`，由 workflow_engine 在启动 role_agent 时注入（复用你现有的 permission gate）。

## 6. 执行语义（引擎如何驱动 agent）

每一步执行流程建议固定为：

1) 绑定输入
2) 生成该 step 的系统提示词（role + step 固定模板）
3) 启动 role_agent 跑 runtime，直到产出结构化结果或超时
4) 校验 output_contract + guards
5) 写入 workflow 事件（start/output/pass 或 guard.fail）
6) 引擎根据 `on_pass/on_fail` 迁移状态

要点：

- 迁移由引擎决定，agent 不能“自己宣布通过”。
- 失败/驳回有明确回环，并受 `max_attempts/timeout` 限制。

## 7. 三省六部制怎么映射成 workflow（v1 可先串行）

一个可落地的 v1 串行版（按你图里的链路对齐）：

- 太子：接旨分拣→立案→交接中书省；最后汇总回奏
- 中书省：接旨→规划→拆解子任务→写 DoD
- 门下省：审议方案→准奏/封驳（驳回必须有理由与修改点）
- 尚书省：派发任务→协调六部→汇总回奏要点
- 六部（专业化产出）：
  - 户部：数据/事实/清单
  - 礼部：文档/表述
  - 兵部：工程实施（代码/系统）
  - 刑部：合规/风险硬门槛
  - 工部：基建/工具链/工程化
  - 吏部：人事/协作/制度（职责边界）

并行（六部同时跑）可以作为 v2：引擎支持 spawn 子步骤/并行 join。

DSL 示例（fixture，当前仅作为模板文件，尚未接入代码执行）：
- `workflows/three-provinces-six-ministries.v1.json`

## 8. 未来：跨机/跨语言（先留档，不挡路）

等本地控制面 + DSL 引擎稳定后，再把某些 step 的 executor 从本地换成远端：

- `executor = local_otp`（v1）
- `executor = http_sse_remote`（未来；参考 `docs/spec/agent-host-protocol.md`）

这样不会改变“制度与语义”，只是把执行位置从本机换到远端。
