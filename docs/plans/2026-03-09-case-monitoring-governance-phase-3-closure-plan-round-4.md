# Phase 3 Round 4 Closure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把第三轮审计剩余的 5 个细粒度制度残差逐项收口，让 Phase 3 从“主链对齐 + 结构项收口”推进到“制度语义也基本闭环”的状态。

**Architecture:** 本轮不重做 Phase 3 主流程，只围绕第三轮审计留下的 5 个缺口做小范围补强：先补 `reconsideration_package` 的版本语义与 `inspect` 写路径并发保护，再补 `urgent_brief` 时间线与 `operation` 异常态，最后决定是否把 `inspection_review.reviewing` 升级为顶层状态。所有变更都以现有对象家族和 EUnit 回归为边界，避免引入新的大对象层级。

**Tech Stack:** Erlang/OTP 28、rebar3、EUnit、本地 JSON 持久化、Cowboy Web API、静态 Web 资产。

**Repo Note:** 本计划基于 `docs/plans/2026-03-09-case-monitoring-governance-phase-3-alignment-audit-round-3.md` 的结论编排；执行时继续使用 `pwsh.exe`，不要回退到 `powershell.exe` 5.x。

---

## Scope Baseline

### Round 4 输入
- 第三轮审计报告：`docs/plans/2026-03-09-case-monitoring-governance-phase-3-alignment-audit-round-3.md`
- 设计稿：`docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-3-inspection-and-reconsideration-loop.md`
- 数据设计稿：`docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`

### Round 4 目标残差
1. `inspection_review` 仍是半对齐四态，不是完整顶层状态机
2. `reconsideration_package` 缺少显式 pack-local 版本号 / 版本显示语义
3. `revision gate` 未覆盖 `inspect_observation_pack`
4. `operation` 只有 happy-path，没有 `partially_applied / failed`
5. `urgent_brief` 还没进入 `timeline.jsonl`

### Round 4 退出条件
- 第三轮报告列出的 5 个残差全部闭合，或明确记录剩余设计决策并形成 ECN / 审计注记
- `rebar3 eunit` 全量通过
- 新的 round-4 收尾结果可直接支撑“Phase 3 已接近零差异”表述

---

## Priority Split

### P0：先补版本语义与并发保护
- 为 `reconsideration_package` 建立显式 pack-local 版本字段
- 为 `inspect_observation_pack` 接入 revision gate

### P1：补派生层制度语义
- 把 `urgent_brief` 写入 `timeline.jsonl`
- 为 `operation` 增加失败态 / 部分成功态

### P2：决定 review 过程态模型
- 决定是否把 `reviewing` 升级为顶层 `state.status`
- 若升级，则同步回归 store / web；若不升级，则在审计结论里显式定稿

---

### Task 1: 为 `reconsideration_package` 引入显式 pack-local 版本字段

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_common_meta.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Checklist:**
- 在 store 测试中先写失败断言：同一个 `observation_pack` 第二次生成卷宗时，第二份 `reconsideration_package` 必须有显式版本字段
- 字段至少包含一个机器可判定值，例如 `links.pack_version` 或 `state.version_no`
- 第二版卷宗必须保留对上一版的 `supersedes_briefing_id`，并与新版本字段同时成立
- 明确版本号增长规则：首版为 `1`，同 pack 下每新建一版单调递增
- 跑定向测试，确认旧链路仍可读、旧断言不被破坏

**DoD:**
- 包级版本号可以从对象本身直接读出，不再只能靠 supersede 链推断
- 测试能区分“首版卷宗”和“同 pack 的后续版卷宗”

---

### Task 2: 补 `reconsideration_package` 的人类可读显示编号语义

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Checklist:**
- 让 `display_code` 或等价展示字段能表达“属于哪个 pack / 第几版卷宗”
- 不要求一次性引入复杂编号体系，但至少要比当前泛化的 `BRIEF-*` 更接近设计稿语义
- preview / overview 页面要能稳定展示新版编号，不因字段升级出现空白或 JS 报错
- store 层和 web 层都补断言，确保编号在后续 supersede 后仍保持可读和可追索

**DoD:**
- 人工查看对象或 Web preview 时，能直接识别“这是同一 observation pack 的第几版卷宗”

---

### Task 3: 为 `inspect_observation_pack` 接入 `current_revision` 乐观并发校验

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_case_governance.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Checklist:**
- 先补 store 层失败测试：`inspect_observation_pack` 在传入过期 revision 时返回 `revision_conflict`
- 再补 web 层冲突测试：HTTP handler 能把冲突稳定映射成现有冲突响应语义
- 实现最小 gate：仅对显式传入 `current_revision` 的调用做校验，不改变旧客户端的兼容性边界
- 冲突响应中带回最新 revision 或足够重试的信息，保持与 create / defer / start 的风格一致

**DoD:**
- Phase 3 所有关键写路径都已纳入同一类 optimistic concurrency 语义

---

### Task 4: 把 `urgent_brief` 事件写入 `timeline.jsonl`

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_finalize_success.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_urgent_brief.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_timeline.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_monitoring_run_test.erl`

**Checklist:**
- 先补失败测试：命中 urgent 条件后，`timeline.jsonl` 中应出现一条急报事件
- 事件至少包含：`event_type`、`case_id`、`summary`、`related_object_refs`、`op_id` 或等价来源信息
- 事件类型命名与现有 reconsideration timeline 保持同一风格，不单独发明平行体系
- 确认 timeline 仍保持 best-effort：timeline 追加失败不能反向阻断 urgent_brief 主动作成功

**DoD:**
- 案件编年史里可见“某次急报触发”的明确痕迹

---

### Task 5: 为 `operation` 增加 `partially_applied / failed` 状态辅助

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_ops.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Checklist:**
- 先补最小状态迁移测试：`pending -> partially_applied` 与 `pending -> failed`
- 补 helper，例如 `mark_partially_applied/4`、`mark_failed/4` 或等价接口
- `failed_steps` 不再只是占位字段，至少要能在测试里验证其落盘内容
- 对调用方只做最小接线，不强求这一轮把每条业务链都做成复杂补偿事务

**DoD:**
- `operation` 不再只有 happy-path 语义，最小异常态已可持久化并可审计

---

### Task 6: 决定并收口 `inspection_review.reviewing` 的顶层状态策略

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
- Modify: `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Checklist:**
- 先做设计决策：`reviewing` 是否要正式升级为顶层 `state.status`
- 如果升级：补 store / web 回归，确保生命周期成为 `pending -> reviewing -> ready_for_reconsideration | insufficient`
- 如果不升级：补一条明确审计注记，说明当前 `process_state` 即为项目接受的最终语义，并更新 round-4 报告
- 无论哪种选择，都要避免 UI / case_state 因新增态或语义说明变化而出现崩溃或错误归类

**DoD:**
- 第三轮报告里关于“inspection_review 半对齐”的结论被正式关闭，而不是继续悬置

---

### Task 7: 执行全量验证并回写 Round 4 收尾结论

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `docs/plans/2026-03-09-case-monitoring-governance-phase-3-alignment-audit-round-3.md`
- Create: `docs/plans/2026-03-09-case-monitoring-governance-phase-3-alignment-audit-round-4.md`
- Verify: `apps/openagentic_sdk/test/openagentic_case_store_monitoring_run_test.erl`
- Verify: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Verify: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Checklist:**
- 跑定向测试，确认 round-4 相关回归全绿
- 再跑全量：`rebar3 eunit`
- 产出一份 round-4 审计结果，明确写出：哪些残差已关闭、是否仍有设计决策未定稿、是否可以对外说“Phase 3 基本零差异”
- 若仍有少量残差，必须写成新的审计尾项，不能口头省略

**DoD:**
- Round 4 有独立结论文档，有验证证据，有剩余差异边界，能够承接下一轮或正式收口

---

## Final Verification Gate

全部任务完成后，统一执行：

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit
```

Expected:
- `0 failures`
- Round 4 涉及的 store / web / monitoring / timeline / operation tests 全绿
- 不回归已收口的 Phase 3 主链能力

---

## Done Definition

只有在以下条件同时满足时，第四轮才算完成：

1. `reconsideration_package` 具备显式 pack-local 版本字段
2. 卷宗显示编号能表达 pack/version 语义
3. `inspect_observation_pack` 支持 `current_revision` 冲突校验
4. `urgent_brief` 事件进入 `timeline.jsonl`
5. `operation` 具备 `partially_applied / failed` 最小异常态
6. `inspection_review` 的 `reviewing` 语义已定稿并验证
7. `rebar3 eunit` 全量通过
8. round-4 审计文档已回写，不再靠口头描述收口状态