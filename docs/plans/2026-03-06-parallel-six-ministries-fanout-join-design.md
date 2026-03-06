# 设计：三省六部工作流并行化（六部 fanout/join）+ 分部 staging 目录（A）

日期：2026-03-06  
范围：`three-provinces-six-ministries.v1`（Erlang/OTP 本地 workflow engine）

## 0. 背景与问题复盘（为什么要改）

当前引擎执行语义是**严格串行**：每个 step 完成后才进入下一个 step。对“三省六部”这类“六部独立产出”的任务，这会造成明显的总耗时浪费。

此外，历史会话里出现过“某一部越权把其它部的活全干了、甚至覆盖总稿”的问题：根因是 `shangshu_dispatch` 产出的 `tasks[]` 被原样注入到每个部，模型在提示词约束不够硬时会“见全清单就全做”。（该问题已通过引擎侧“按 role 过滤 tasks 输入”修复，但并行化时仍需把边界规则写进提示词与落盘路径约束，形成 defense-in-depth。）

## 1. 目标（DoD）

1) **六部并行**：`hubu/libu/bingbu/xingbu/gongbu/libu_hr` 六个部门 step 可以同时执行，整体用时接近“最慢的那个部门”的用时，而不是六者相加。  
2) **分部 staging 目录（用户选择 A）**：每一部只写自己目录，避免互相覆盖：
   - `workspace:staging/hubu/...`
   - `workspace:staging/libu/...`
   - `workspace:staging/bingbu/...`
   - `workspace:staging/xingbu/...`
   - `workspace:staging/gongbu/...`
   - `workspace:staging/libu_hr/...`
3) **join 语义简单**：join 只负责“等待六部都完成（或失败策略触发）并汇集 outputs”，不做复杂二次加工；后续仍可保留 `shangshu_aggregate -> taizi_reply` 作为串行收束步骤。  
4) **可观测性不倒退**：Web UI 仍可通过 workflow session 的 SSE 观察各部事件流，并可对 HITL 问答正常响应。  

## 2. 非目标（本轮不做）

- 不做跨机/远端并发 executor（仍是本机并发进程）。
- 不做“真正的任务队列/调度中心/优先级抢占”。
- 不强行引入“单写者总稿”策略；总稿可由汇总 step 合编，但六部 staging 文件必须各写各的目录、互不覆盖。

## 3. 关键约束（决定设计边界）

### 3.1 workflow session 的 event log 不能被并发写

当前 `openagentic_session_store:append_event/3` 的 `seq` 通过读取 `events.jsonl` 推断下一号，**并发 append 会竞态，导致 seq 重复/乱序/数据损坏**。

而 `default_step_executor` 通过 `event_sink=BridgeSink` 把每个 step session 的事件桥接到 workflow session（写入 `workflow.step.event`）。并行六部意味着会有多个 step session 同时向 workflow session 追加桥接事件。

因此：并行化必须同时解决“workflow session 事件串行化写入”的问题。

### 3.2 分部落盘路径必须可机器检查

仅靠“提示词说不要写别人的文件”不够；应做到：
- 任务清单与提示词都使用固定路径模板（本部目录）
- PermissionGate / 工具层最好也能做最小限制（可选增强）

## 4. 方案选型

### 方案 A（推荐）：并行 step + 中心化 workflow 事件写入（mailbox router）

核心思路：
- 六部 step 并行执行，但**禁止**它们直接调用 `append_wf_event` 写 workflow session。
- 把 `BridgeSink` 改为“发消息给 workflow engine（或专门 router 进程）”，由中心进程**单线程**顺序写入 workflow session，保证 `seq` 递增与文件一致性。

优点：
- 对现有 session_store 改动最小（无需全局锁/原子计数器）
- 并发复杂度集中在 workflow engine 内部，可控
- Web UI 的 workflow SSE 不会被破坏

代价：
- workflow engine 需要一个接收/排队/落盘事件的循环（注意吞吐与 backpressure）

### 方案 B：让 `append_event/3` 变成并发安全（文件锁/原子 seq）

优点：所有地方都可以并发 append。  
代价：实现与跨平台一致性更复杂（Windows 文件锁语义、崩溃恢复、性能），且会影响全系统，不建议先走这条路。

结论：采用方案 A。

## 5. DSL 扩展提案：`fanout_join` 编排节点

为了保持“普通 step 仍是串行状态机”的简单性，引入一个显式的并发编排节点（不调用 LLM）：

### 5.1 新 step 字段（示例）

在某个 step（例如 `shangshu_dispatch`）的 `on_pass` 之后，新增一个 `fanout_join` step：

- `id`: `six_ministries_fanout`
- `role`: `shangshu`（或专用 `workflow_engine` 角色；不进入 LLM）
- `executor`: `fanout_join`（新增 executor 类型）
- `fanout`:  
  - `steps`: `[ "hubu_data", "libu_docs", "bingbu_engineering", "xingbu_compliance", "gongbu_infra", "libu_hr_people" ]`
  - `join`: `"shangshu_aggregate"`
  - `max_concurrency`: `6`（可选；未来允许按 CPU/IO 限流）
  - `fail_fast`: `false`（可选；默认等所有结果，再由 join/guards 决定）

并且把原先串行链路改为：

`shangshu_dispatch -> six_ministries_fanout -> shangshu_aggregate -> taizi_reply`

六部各 step 的 `on_pass/on_fail` 不再串成链，而是终止于 `null` 或回到自己（重试），由 `fanout_join` 汇合决定是否进入 `shangshu_aggregate`。

### 5.2 join 的输入绑定

`shangshu_aggregate` 的 `input.merge.sources` 维持不变（仍可 merge 六部 outputs），但应保证六部 outputs 已在 `fanout_join` 完成后被写入 `State.step_outputs`。

## 6. 执行语义：fanout/join 的最小实现

1) `fanout_join` 启动：对 `fanout.steps` 逐个 spawn 子进程执行 `run_one_step` 的“无递归版本”（只跑该 step 自身，不再按 `on_pass` 继续）。  
2) 子进程执行时：
   - 仍创建各自 `step_session_id`
   - 仍走 runtime/tool-loop
   - 但其 `BridgeSink` 不再直接落盘 workflow session，而是把桥接事件发送给中心 router
3) 中心 router 串行落盘所有 workflow events（含 `workflow.step.event`）。  
4) 收集结果：`fanout_join` 等待 6 个子进程完成，形成 `{StepId -> {ok, Parsed/Out} | {error, Reasons}}`。  
5) 汇合策略：
   - 若全部 `ok`：写入对应 `workflow.step.output`/`workflow.step.pass`（对每个 step），然后 transition 到 `join`（例如 `shangshu_aggregate`）
   - 若存在失败：按 `fail_fast`/重试策略决定是否重跑失败 step、或回到 `shangshu_dispatch`、或直接 workflow failed（策略需要在 DSL 明确）

## 7. 分部 staging 目录规范（A）

对“创作/文案类”的三省六部：

- 每部任务默认产物路径：
  - `workspace:staging/<ministry>/poem.md`
  - （如需多文件）允许 `workspace:staging/<ministry>/*.md`，但禁止跨目录写入

提示词必须包含硬约束（每部一致）：
- 只执行 `ministry=<本部>` 的任务
- 只允许写入 `workspace:staging/<本部>/...`（以及本部 DoD 明确要求的其它路径）
- 禁止写入其它部目录与 `workspace:deliverables/*`

可选增强（非硬要求）：在工具层对 `Write/Edit` 增加路径 allowlist（按 role 注入），把“只能写本部 staging 目录”变成硬门槛。

## 8. 可观测性与事件桥接（必须改）

### 8.1 新增 workflow 事件路由器（单线程 append）

在 workflow engine 进程内维护：
- `append_wf_event/2` 只能在主进程调用
- 子 step 进程的 `BridgeSink` 改为 `ParentPid ! {wf_bridge, StepId, StepSessionId, Ev, Extra}`
- 主进程按消息到达顺序 append `workflow.step.event`

### 8.2 backpressure（最小约束）

并发时 `assistant.delta` 事件频繁，容易导致消息洪峰。最小策略：
- 对 `assistant.delta` 可以采样/合并（例如每 N 条合一条，或仅保留关键事件：tool.use/tool.result/user.question/assistant.final）
- 或者 router 对 delta 做“最多每秒 X 条”限流

（具体策略实现可延后，但必须在设计里承认并预留接口。）

## 9. 测试与验证（实现时的门禁）

1) **EUnit：fanout 基本语义**：6 个并行 step 都能跑完，join 后进入汇总 step。  
2) **EUnit：workflow session seq 单调**：并发桥接事件下 `events.jsonl` 的 `seq` 无重复、可解析。  
3) **路径隔离**：通过任务输入 + 提示词约束，验证六部仅写入 `workspace:staging/<ministry>/`（可用 fake tool 或检查写入日志）。  
4) **回归**：保持现有串行 workflow 行为不变（并行仅在 DSL 声明 `executor=fanout_join` 时启用）。

## 10. 迁移步骤（实现清单）

1) 扩展 DSL schema + validator：允许 step `executor=fanout_join` + `fanout{steps/join/...}` 字段  
2) workflow engine：实现 `fanout_join` executor（spawn/wait/汇合写 State）  
3) workflow engine：引入中心 router，串行写 workflow session event log（解决并发 append 竞态）  
4) 更新 `three-provinces-six-ministries.v1.json`：插入 `six_ministries_fanout`，六部 step 从“串行链”改为“并行叶子”  
5) 更新六部提示词：统一加入“只写本部 `workspace:staging/<ministry>/...`”硬约束，并在 `shangshu_dispatch` 的 DoD 中固定路径模板  
6) 补 eunit：并行/事件/路径隔离

---

## 需要你确认的 1 个点（实现前）

`workspace:staging/<ministry>/` 下面的文件命名你倾向：
- 固定单文件：`poem.md`（简单、可 join）
- 还是按部名：`hubu.md` / `gongbu.md`（但仍在各自目录下）

我建议固定 `poem.md`，join 时结构最稳定。

