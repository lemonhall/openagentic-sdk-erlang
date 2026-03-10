# 2026-03-09：Phase 3｜第二轮全量对齐审计

## 1. 审计范围
- 设计输入：
  - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-3-inspection-and-reconsideration-loop.md`
  - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`
  - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`
- 实现范围：
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_reconsideration_rules.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_action.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_preview.erl`
  - `apps/openagentic_sdk/priv/web/view/reconsideration-preview.html`
  - `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- 验证范围：
  - `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`
  - 全量 `rebar3 eunit`

## 2. 第二轮一句话判断

**如果只看第一轮 closure plan 覆盖的 7 项，Phase 3 已经完成并通过验证；但如果按 Phase 3 设计稿做第二轮“全量扫描”，仍能发现 5 类未被上一轮纳入的制度差异。**

换句话说：

- **核心主链已经基本对齐**；
- **但全量设计稿并未被完全吃透**；
- 当前更准确的说法应是：**Phase 3 核心闭环已收口，仍存在若干架构级 / 制度级增强缺口。**

---

## 3. 第二轮确认“已对齐”的部分

以下部分在第二轮复核中继续确认为已落地：

### 3.1 observation pack / inspection / reconsideration 主链已成立
- `observation_pack`、`inspection_review`、`reconsideration_package` 都是正式对象；
- Web 创建 / inspect / preview / defer / start 全链路存在；
- store / web / static page / 全量 EUnit 均已验证。

### 3.2 review adoption 回链已成立
- `inspection_review.links.derived_briefing_id` 已在生成卷宗后回填；
- 这条关系在 store 与 Web 返回对象里都可追索。

### 3.3 deferred/stale/superseded 门禁已进入执行逻辑
- `start_reconsideration/2` 不再只看状态字面值；
- 已在 start 前重新校验 freshness 与 supersede 条件；
- stale / superseded 的 Web `409` 也已经固定。

### 3.4 frozen payload 与 preview 已具备最小制度语义
- 已冻结 `based_on_round`、`baseline_facts`、`change_facts`；
- 已展示 controversies 正文与生命周期提示；
- 新 round 的 session 已装配 `reconsideration_context`。

### 3.5 pack/review 规则已从静态字段升级为执行化 helper
- `completeness_rule` 已支持默认模式与 `min_report_count`；
- `inspection_rule` 已进入 review 状态判定；
- `trigger_policy = manual` 的“默认不自动出卷宗”语义已被测试固定。

---

## 4. 第二轮新增发现的差异

下面这些不是第一轮 7 项计划里的内容，但在第二轮全量扫描时，仍然与设计稿存在明显差异。

### 4.1 `inspection_review` 仍然缺少过程态，只有终态快照

设计稿里建议 `inspection_review` 至少具备：
- `pending`
- `reviewing`
- `ready_for_reconsideration`
- `insufficient`

当前实现仍然是“一次调用直接产出最终快照”：
- `inspect_observation_pack/2` 直接写出最终 review；
- 代码中没有 `pending` / `reviewing` 的流转；
- 测试也只覆盖 `ready_for_reconsideration` 与 `insufficient`。

这意味着：
- **“有检察对象”已对齐**；
- **“检察过程态机”仍未对齐**。

### 4.2 `urgent_brief` / 重大异常急报尚未落地

设计稿在“常报、急报与督办机制”里明确写了：
- 命中重大异常阈值时，可直接生成 `urgent_brief`；
- 急报投递到内邮；
- 急报不替代整包复议。

当前代码表现为：
- `reconsideration_package.spec.included_urgent_refs` 固定为 `[]`；
- 没有独立的 `urgent_brief` 对象家族；
- 没有对应的 Phase 3 急报 mail / Web / 测试主链。

这属于**设计稿明确写出、但当前实现仍为空位**的差异。

### 4.3 Phase 3 跨对象动作仍未引入显式 `operation` 落盘

数据设计文档对跨对象动作给出的要求是：
- `start_reconsideration`
- `defer_briefing`
- 以及其他跨对象更新

都应通过显式 `operation` 记录落盘，而不是只做多文件 best-effort 更新。

当前实现里：
- Phase 3 动作会同时更新 pack / review / package / case / round / mail；
- 但 `meta/ops/<op_id>.json` 没有落盘实现；
- `source_op_id` 在相关 mail 上仍常为 `undefined`；
- 没有 Phase 3 operation 的读取、索引或测试。

所以这块仍是**架构层未完成项**，不是文档想象出来的增量。

### 4.4 `timeline.jsonl` 级里程碑时间线尚未落地

数据设计文档要求：
- `case` 级有统一 `timeline.jsonl`；
- 记录诸如 pack ready、briefing deferred / superseded / consumed、复议开启等里程碑事件；
- timeline 为派生层，不阻塞主流程。

当前实现里：
- 已有 `meta/history.jsonl` 与对象级 history；
- 但没有 `timeline.jsonl` 路径与写入逻辑；
- 也没有 Phase 3 里程碑事件外壳与补写机制。

所以这部分仍然**停留在设计层，未进入代码层**。

### 4.5 Phase 3 动作未接入乐观并发校验

数据设计文档要求：
- 对象带 `revision`；
- 关键更新要有乐观并发校验；
- 对外可返回 `revision_conflict`。

当前 Phase 3 实现里：
- 对象 header 的 `revision` 会自然增长；
- 但 `create_observation_pack` / `inspect_observation_pack` / `create_reconsideration_package` / `defer_reconsideration_package` / `start_reconsideration` 都没有 `current_revision` 输入与 compare-and-set 校验；
- 相应 Web API 也没有 Phase 3 的 `revision_conflict` 映射和回归测试。

因此，这块仍属于**并发语义未补齐**。

---

## 5. 第二轮的边界判断

不是所有差异都应该被当作“必须立即返工”。第二轮更重要的是把差异分层。

### 5.1 属于“核心主链已完成，但制度增强未补”的差异
- `inspection_review` 过程态
- `urgent_brief` / 急报主链
- `operation` 落盘
- `timeline` 派生层
- 乐观并发校验

### 5.2 不应再回退成“Phase 3 还没做完”的差异
这些差异并不推翻第一轮收口结论，因为以下主链已经是成立的：
- pack -> inspect -> package -> preview -> defer/start
- review adoption backlink
- deferred stale/superseded gate
- frozen payload / reconsideration context
- overview/indexes 暴露

所以第二轮的正确结论不是“第一轮白做了”，而是：

**第一轮收口的是 Phase 3 核心闭环；第二轮发现的，是设计稿里更深一层的制度 / 架构项。**

---

## 6. 建议作为第三轮候选清单的 5 项内容

如果要继续做第三轮对齐，建议优先级如下：

1. **P0：显式 operation 落盘**
   - 为 `create_reconsideration_package` / `defer_reconsideration_package` / `start_reconsideration` 建立 `meta/ops` 记录；
   - 让 `source_op_id` 真正可追索。

2. **P0：补 `timeline.jsonl`**
   - 以 best-effort 方式记录 pack ready、package deferred / superseded / consumed、round started 等事件；
   - 不阻塞主业务。

3. **P1：引入 Phase 3 revision gate**
   - 为关键 Web 动作增加 `current_revision`；
   - 返回 `revision_conflict`；
   - 补 store / web 回归测试。

4. **P1：补 `urgent_brief` 主链**
   - 明确对象与 mail 类型；
   - 让 `included_urgent_refs` 不再长期为空占位。

5. **P2：把 inspection 从“结果快照”扩成“过程态机”**
   - 补 `pending` / `reviewing`；
   - 保持现有终态对象兼容。

---

## 7. 第二轮最终结论

**第二轮全量扫描后的结论是：Phase 3 已经完成核心对齐，但并没有“把设计稿的所有层次都吃干净”。仍然存在 5 类明确、具体、可施工的剩余差异。**

因此，对外表述建议改成：

- **Phase 3 核心闭环：已收口并通过验证**；
- **Phase 3 全量设计稿：仍有第三轮对齐空间**。

