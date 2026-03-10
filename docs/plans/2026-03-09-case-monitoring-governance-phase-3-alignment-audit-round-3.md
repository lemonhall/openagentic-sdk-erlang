# 2026-03-09：Phase 3｜检察验卷与复议闭环第三轮对齐审计

## 文档状态
- 状态：第三轮全量对齐审计 / 实现快照
- 处理状态：【已完成】
- 审计时间：2026-03-09
- 审计对象：Phase 3 设计稿、数据设计稿与仓库当前实现
- 审计目标：回答 **在第二轮 5 项收口完成之后，Phase 3 与设计稿之间是否还有第三轮剩余差异**

---

## 1. 本轮审计使用的基线

### 1.1 设计基线
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-3-inspection-and-reconsideration-loop.md`
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`

### 1.2 对照的现实实现
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_reconsideration_rules.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_ops.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_timeline.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_finalize_success.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_urgent_brief.erl`
- `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
- `apps/openagentic_sdk/src/openagentic_web.erl`
- `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- `apps/openagentic_sdk/test/openagentic_case_store_monitoring_run_test.erl`
- `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

### 1.3 新鲜验证证据
- 定向回归：
  - `. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_monitoring_run_test --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test`
- 全量回归：
  - `. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit`
- 结果：
  - `227 tests, 0 failures`

---

## 2. 第三轮一句话判断

**第二轮列出的 5 类结构差异已经基本收口；但如果继续按设计稿做第三轮全量扫描，仍然可以识别出 5 类更窄、更深、但依然真实存在的剩余差异。**

换句话说：
- **Phase 3 的核心业务闭环已成立并通过全量验证**；
- **第二轮的主缺口已不再成立**；
- **但若对外宣称“与设计稿完全无差异”，现在还为时过早。**

---

## 3. 本轮确认已闭合的第二轮差异

### 3.1 `operation` 已正式落盘
- Phase 3 动作现在会写入 `meta/ops/<op_id>.json`。
- `create_reconsideration_package`、`defer_reconsideration_package`、`start_reconsideration`、`inspect_observation_pack` 都已进入 operation 记录。
- `reconsideration_ready` 内邮的 `links.source_op_id` 也已回填，不再长期为 `undefined`。

### 3.2 `timeline.jsonl` 已落地
- `case` 级 `meta/timeline.jsonl` 已存在。
- 当前至少会写入：
  - `observation_pack_ready / observation_pack_inspected`
  - `reconsideration_package_created`
  - `reconsideration_package_deferred`
  - `reconsideration_package_superseded`
  - `reconsideration_round_started`
- 写入方式为 best-effort，不阻断主业务动作。

### 3.3 Phase 3 关键卷宗动作已接入 `revision gate`
- `create_reconsideration_package`
- `defer_reconsideration_package`
- `start_reconsideration`

以上三类动作已经支持 `current_revision`，并在 store / Web 层返回 `revision_conflict`。

### 3.4 `urgent_brief` 主链已落地
- 监测运行命中重大异常后，已能生成 `urgent_brief` 对象。
- 同时会投递 `message_type = urgent_brief` 的内邮。
- `reconsideration_package.spec.included_urgent_refs` 也已不再固定为空。

### 3.5 `inspection_review` 已具备可追索过程态痕迹
- review 不再只有一个终态快照。
- 当前至少会先落一个 `pending` review，再更新到最终态。
- `ext.status_history` 已能追索过程痕迹，预览页也能显示 `process_state / status_history`。

---

## 4. 第三轮新增发现的剩余差异

下面这些差异不再是“主链没打通”，而是设计稿更深一层的制度语义尚未完全吃透。

### 4.1 `inspection_review` 过程态是“半对齐”，还不是完整状态机
设计稿对 `inspection_review` 的状态建议是：
- `pending`
- `reviewing`
- `ready_for_reconsideration`
- `insufficient`

当前实现已经补出了：
- `state.status = pending`
- `state.process_state = reviewing`
- 最终态 `ready_for_reconsideration / insufficient`
- `ext.status_history = [pending, final]`

但仍然存在一个很具体的残差：
- **`reviewing` 目前只是 `process_state`，不是一条独立持久化的 `state.status` 状态节点。**
- 也就是说，代码已经补上“过程存在”，但还没有完全对齐成设计稿字面上的四态状态机。

这属于：
- **主链已对齐**；
- **状态语义仍是部分对齐**。

### 4.2 `reconsideration_package` 仍缺少“第几版卷宗”的显式版本语义
设计稿在“卷宗包生命周期：deferred、快照与版本链”里要求：
- 同一个 `observation_pack` 下可有多版卷宗；
- 卷宗包应具备明确版本号与先后链条；
- 展示编号应能表达“属于哪个 case / pack / 第几版卷宗”。

当前实现里：
- 已有 `supersedes_briefing_id` 链条；
- 已有 `display_code`；
- 但 `display_code` 仍是通用 `BRIEF-*` 随机编号；
- **没有 pack-local 的显式版本号 / 序号字段。**

因此当前更准确的结论是：
- **先后链条已对齐**；
- **版本号与人类可读编号语义尚未完全对齐。**

### 4.3 `revision gate` 仍只覆盖了卷宗动作，未覆盖 `inspect_observation_pack`
数据设计稿对并发写入的原则是：
- 元数据对象写入应有 `revision`；
- 关键更新应进行乐观并发校验。

当前 Phase 3 中：
- `create_reconsideration_package / defer_reconsideration_package / start_reconsideration` 已接入；
- 但 `inspect_observation_pack/2` 仍会修改现有 `observation_pack`， yet 没有可选 `current_revision` 校验；
- 对应的 Web `inspect` handler 也没有 `revision_conflict` 回路测试。

因此这里仍是一个**范围收窄后的并发残差**：
- 不是“完全没有 gate”了；
- 而是“gate 还没有覆盖到 inspect 这条写路径”。

### 4.4 `operation` 状态机目前只有 happy-path，缺少 `partially_applied / failed`
数据设计稿对 `operation` 至少建议：
- `pending`
- `applied`
- `partially_applied`
- `failed`

当前实现里：
- 已有 `pending`
- 已有 `applied`
- 已有 `failed_steps` 字段占位
- 但没有 `mark_partially_applied/…` 或 `mark_failed/…` 一类 helper
- 也没有任何测试覆盖部分落盘/失败落盘后的 operation 状态

所以现在的真实情况是：
- **operation 对象已经存在**；
- **但 operation 的异常态语义仍未实现完整。**

### 4.5 `urgent_brief` 已落对象与内邮，但还没进入 `case timeline`
数据设计稿对 `timeline.jsonl` 的举例里明确包含：
- 某急报触发
- 某卷宗被 deferred
- 某次复议正式开启

当前实现里：
- 复议链相关事件已经写入 timeline；
- `urgent_brief` 已生成对象并投递内邮；
- 但 **urgent brief 触发本身尚未被追加为 `timeline.jsonl` 事件。**

因此这块属于：
- **急报主链已对齐**；
- **急报的案卷编年史记录仍未补齐。**

---

## 5. 第三轮边界判断

### 5.1 哪些结论现在可以稳定成立
现在已经可以稳定成立的说法是：
- `observation_pack -> inspection_review -> reconsideration_package -> preview -> defer/start` 主链成立；
- `urgent_brief` 已进入对象层与内邮层；
- `operation / timeline / revision gate / process trace` 已经从“没有”进入“有”；
- 全量 EUnit 已通过，说明当前实现不是纸面对齐，而是行为对齐。

### 5.2 哪些说法现在仍不准确
以下表述现在仍不严谨：
- “Phase 3 与设计稿已经完全无差异”
- “inspection 已具备完整过程态机”
- “卷宗包版本语义已经完全到位”
- “所有 Phase 3 写路径都已接入 optimistic concurrency”
- “operation/timeline 的制度语义已经全部补齐”

---

## 6. 如果继续做第四轮，建议优先级

### P0
1. 为 `reconsideration_package` 引入显式 pack-local 版本号 / 显示编号规则
2. 为 `inspect_observation_pack` 接入 `current_revision` 并补 store / web 冲突测试

### P1
3. 把 `urgent_brief` 事件写入 `timeline.jsonl`
4. 为 `operation` 增加 `partially_applied / failed` 状态辅助与回归测试

### P2
5. 决定是否把 `reviewing` 升级为顶层 `state.status` 的正式过渡态，而不只放在 `process_state`

---

## 7. 第三轮最终结论

**第三轮全量扫描后的结论是：Phase 3 现在已经达到“主链对齐 + 第二轮结构差异已收口”的状态，但仍保留 5 个更细粒度的制度残差。**

因此，对外表述建议更新为：
- **Phase 3 核心与第二轮结构项：已收口并通过全量验证**；
- **Phase 3 与设计稿的最终完全对齐：仍存在第四轮的小范围收尾空间。**
