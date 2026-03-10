# 2026-03-09：Phase 3｜检察验卷与复议闭环实现对齐审计

## 文档状态
- 状态：首次对齐审计 / 实现快照
- 处理状态：【已完成】
- 审计时间：2026-03-09
- 审计对象：仓库当前已落地的 Phase 3 相关实现
- 审计目标：回答 **Phase 3 设计稿里哪些已经落地，哪些只落了一半，哪些仍是下一轮必须补齐的缺口**

---

## 1. 为什么要有这份文档
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-3-inspection-and-reconsideration-loop.md` 已经给出了本阶段的目标、边界、DoD 与数据骨架。
- 但当前仓库并不是“Phase 3 还没开始”，而是已经出现了一条可运行主链：
  - `observation_pack`
  - `inspection_review`
  - `reconsideration_package`
  - `internal_mail`
  - 复议卷宗预览页
  - `开启复议 / 继续观察`
- 如果不先做实现审计，下一轮施工很容易出现三类偏差：
  - 把已落地的 Phase 3 主链重写一遍；
  - 把真正的缺口和 Phase 4 的聚合/审计增强混在一起；
  - 让 PRD、代码、Web 页面和测试再次漂移。

因此，这份文档不是替代 Phase 3 设计稿，而是作为“**当前现实与 Phase 3 目标之间的对齐说明书**”，供后续收口施工直接引用。

---

## 2. 规范来源与现实证据

### 2.1 本轮对齐以哪些设计文档为准
本轮“应该做到什么”的判断，主要以以下文档为准：

1. Phase 3 直接施工基准：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-3-inspection-and-reconsideration-loop.md`

2. 全局产品与生命周期基线：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`

3. 配套数据与 schema 基线：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`

### 2.2 本轮现实审计主要看的实现文件
- 核心主链：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_repo_paths.erl`
  - `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_repo_readers.erl`

- Web API：
  - `apps/openagentic_sdk/src/openagentic_web.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_cases_overview.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_observation_packs.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_observation_pack_inspect.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_packages_create.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_preview.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_action.erl`

- Web 页面与前端：
  - `apps/openagentic_sdk/priv/web/view/reconsideration-preview.html`
  - `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
  - `apps/openagentic_sdk/priv/web/assets/inbox.js`

- 测试证据：
  - `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_static_page_test.erl`

### 2.3 本轮验证证据
本轮不是只靠“读代码猜测”，而是做了新鲜验证：

- 运行命令：
  - `. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test`
  - `. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit`

- 结果：
  - `2 tests, 0 failures`
  - `217 tests, 0 failures`

这意味着下文对“当前现实”的描述，不只是静态阅读结论，而是至少经过了相关主链与全量 EUnit 的新鲜验证。

---

## 3. 一句话总判断

**截至 2026-03-09 本轮收口完成后，仓库里的 Phase 3 已经从“第一版可运行闭环”进入“与 PRD 基本对齐”的状态：观察包、检察验卷、冻结卷宗、卷宗预览、继续观察 / 开启复议、stale / superseded 再校验、复议 session 上下文装配、以及总览 / 索引暴露都已落地并经过测试验证。**

换句话说：

- **Phase 3 主链已不应再被描述为“仅第一版闭环”**；
- **本轮缺口已经收口到“基本对齐”**；
- 后续若继续细化，重点应放在 inspection 过程态丰富化与少量 links/ext 纯化，而不是重做主链骨架。

---

## 4. 已经对齐的部分

### 4.1 `observation_pack` 已经是一等对象，且能按任务组装材料
当前实现已经不再把“是否可复议”挂在单个任务上判断，而是显式创建 `observation_pack`：

- 保存 `title`、`target_question`、`task_bindings`、`freshness_window`、`completeness_rule`、`inspection_rule`、`trigger_policy`；
- 根据任务绑定读取最新 `fact_report`；
- 计算 `ready_score`、`missing_requirements`、`latest_ready_at`；
- 把 `active_pack_ids` 反写到对应任务上。

这与 Phase 3 文档关于“观察包是复议触发单元，而不是按单任务零散判断”的主张基本一致。

### 4.2 `inspection_review` 已经落盘，且能生成争议清单
当前 `inspect_observation_pack/2` 已经会：

- 对 observation pack 做一次独立检察快照；
- 保存 `reviewed_run_ids`、`reviewed_report_ids`；
- 生成 `controversy_candidates`；
- 给出 `ready_for_reconsideration` 或 `insufficient` 的结论；
- 将结果回挂到 `observation_pack.links.current_inspection_review_id`。

这说明“检察官验卷”已经不是 UI 文案，而是有真实对象、真实状态和真实落盘的能力。

### 4.3 `reconsideration_package` 已经是冻结快照，而不是现场动态现拼
当前 `create_reconsideration_package/2` 已经会：

- 只允许从 `ready_for_reconsideration` 的检察结果生成卷宗；
- 保存 `included_report_refs`、`included_resolution_ref`、`included_controversy_refs`；
- 保存 `frozen_payload`；
- 为卷宗分配独立 `display_code`；
- 生成一封 `reconsideration_ready` 内邮。

这与 Phase 3 文档“卷宗包必须是冻结快照”的方向是一致的。

### 4.4 Web 已经有完整的预览入口与动作入口
当前 Web 层已经提供：

- 创建 observation pack 的 API；
- 对 pack 发起 inspection 的 API；
- 生成 reconsideration package 的 API；
- 获取卷宗预览的 API；
- `defer` / `start` 动作 API；
- 静态卷宗预览页；
- Inbox 中的“查看卷宗”入口。

也就是说，用户体验上已经出现了“先阅卷，再决定是否开复议”的真实交互路径，而不是仅有后端对象。

### 4.5 `deferred / superseded / consumed_by_round` 主链已经存在
当前实现已经维护了三条关键生命周期链：

- 卷宗被“继续观察”后进入 `deferred`；
- 新卷宗生成时，上一份 live 卷宗会被标记为 `superseded`；
- 点击“开启复议”后，卷宗进入 `consumed_by_round`，并记录 `consumed_by_round_id`。

这意味着 Phase 3 DoD 里最关键的生命周期骨架已经具备。

### 4.6 “一键复议”的底层语义基本对齐
当前 `start_reconsideration/2` 已经不是续写旧 session，而是：

- 在同一个 `case` 下新建 `deliberation_round`；
- 创建新的 `workflow_session_id`；
- 将 `reconsideration_package_id`、`triggering_briefing_id`、`input_material_refs` 挂到新 round；
- 将案卷 phase 推进到 `reconsideration_in_progress`。

这与主 PRD §8.7 的方向是对齐的。

---

## 5. 仍属“可继续细化”、但已不构成收口阻塞的部分

### 5.1 readiness / inspection 规则已经执行化，但仍是保守版制度执行器
当前实现已经不再只是存字段：

- `completeness_rule` 已支持默认 `all_required_reports_present` 与 `min_report_count`；
- `inspection_rule` 已支持默认人工检察结论，以及基于 `blocking_issues` 的 gate；
- `trigger_policy.mode = manual` 的“不自动生成卷宗”语义，已通过主链与测试固定下来。

但这仍然是保守版规则执行器，而不是完整规则引擎；后续若扩展更多 rule mode，应继续在独立 helper 中演进。

### 5.2 `inspection_review` 仍偏“结果快照”，而不是完整过程态机
PRD 提到的 `pending / reviewing / ready_for_reconsideration / insufficient` 四态中，当前实现仍主要落到最终结论态：

- `ready_for_reconsideration`
- `insufficient`

因此，“检察结果对象化”已经对齐，但“检察过程态机”仍可在后续增强。

### 5.3 `frozen_payload` 已具备卷宗语义骨架，但仍是保守组装版
本轮后，`frozen_payload` 已补上：

- `based_on_round`
- `baseline_facts`
- `change_facts`
- `summary.controversies`
- 更明确的复议 session 上下文装配来源

这已经足以支撑 PRD 所要求的“默认读冻结卷宗而不是重啃全文”语义；但若继续追求更正式的上呈材料表达，仍可再细化模板化摘要与更丰富的事实分类。

### 5.4 预览页已具备制度语义所需关键信息，但还不是重型阅卷工作台
当前预览页已经能展示：

- 生命周期提示（`ready / deferred / superseded / consumed_by_round`）；
- 上一轮基线与本轮变化事实；
- controversy 正文面板；
- 复议动作前后的状态刷新。

这已经满足 Phase 3 收口要求；后续若要继续增强，可再往“多栏阅卷工作台”演进，但这已属于体验升级，不是闭环缺口。

### 5.5 生命周期回链已基本闭合，剩余是结构纯化问题
当前实现已经形成：

- `inspection_review.links.derived_briefing_id`
- `reconsideration_package.links.supersedes_briefing_id`
- `reconsideration_package.links.consumed_by_round_id`
- overview / indexes 中对相关对象与状态的稳定暴露

剩余可选优化主要是把个别历史兼容字段从 `ext` 再进一步纯化到 `links`；这不再阻塞 Phase 3 与 PRD 的基本对齐判断。

---

## 6. 本轮已补齐、并支撑“基本对齐”判断的关键项

### 6.1 review ↔ package adoption 回链已经补齐
`inspection_review.links.derived_briefing_id` 现在会在生成卷宗后回填，因此 review 已能回答“我是否已被正式卷宗采用”。

### 6.2 `deferred / superseded / stale` 已进入 start gate
`start_reconsideration/2` 现在会在动作前重新校验：

- 当前卷宗是否已被 supersede；
- observation pack 的 freshness 是否仍然有效；
- 当前 completeness 规则是否仍然满足。

这让 deferred 卷宗从“状态存在”升级为“制度约束被执行”。

### 6.3 新复议 session 已真正装配 `reconsideration_context`
新 round 的 `workflow_session_id` 在创建时已经携带：

- `package_id`
- `package_display_code`
- `package_status`
- `frozen_payload`

并且首条 `system.init` 事件也会落下同源上下文，这使“默认读卷宗”的复议启动语义真正成立。

### 6.4 冻结卷宗已补齐基线 / 变化 / 争议的最小结构化表达
`frozen_payload` 现在已经冻结：

- 上一轮 `based_on_round`
- `baseline_facts`
- `change_facts`
- `summary.controversies`

这让卷宗从“可读快照”升级成“带最小制度语义的正式复议材料”。

### 6.5 总览、索引与状态分组已经跟上 Phase 3 主链
overview 现在会稳定暴露：

- `observation_packs`
- `inspection_reviews`
- `reconsideration_packages`

索引目录也已补上 `inspection-reviews-by-status.json`，并持续写出 `reconsideration-packages-by-status.json`，用于稳定承载 `ready / deferred / superseded / consumed_by_round` 等生命周期状态。

---

## 7. 当前不应误判为缺口的部分

### 7.1 Observation pack 目前主要通过显式创建进入系统，是可接受的
Phase 3 当前 DoD 重点是：

- 能按观察包聚合；
- 能做检察；
- 能出卷宗；
- 能预览并行动。

它并没有要求本轮必须把“观察包自动规划 / 自动分组策略”也一起做完。

因此，**当前以 API 显式创建 pack，并不构成 Phase 3 未完成。**

### 7.2 预览页现在偏简，不等于主链无效
预览页现在确实偏薄，但它已经完成了本阶段最关键的两个动作：

- 让你在正式复议前看到卷宗快照；
- 让你明确做出“开启复议 / 继续观察”的决策。

所以这更像“内容密度不足”，而不是“闭环不存在”。

---

## 8. 本轮审计后的明确结论

截至 2026-03-09，可以明确下结论：

1. **Phase 3 主链已经落地，不应再被描述为“待实现”**
   - Observation pack、inspection review、reconsideration package、mail、preview、start/defer action 均已存在，且有测试验证。

2. **Phase 3 现在可以视为“已与 PRD 基本对齐”**
   - 卷宗内容语义已补到 `based_on_round / baseline_facts / change_facts / controversies`；
   - 规则执行化、deferred 再校验、review/package 回链、复议上下文装配都已落地并有回归测试覆盖。

3. **下一轮若继续演进，应以细化而非重写为主**
   - 应继续复用现有 case store 主链、现有 Web API、现有页面与现有 EUnit；
   - 后续重点是 inspection 过程态、UI 阅卷体验与少量 links/ext 纯化，而不是推倒重来。

---

## 9. 可直接转化为施工计划的对齐清单

本轮收口已完成的对齐项如下：

- [x] 在生成卷宗后回填 `inspection_review.links.derived_briefing_id`
- [x] 在 `start_reconsideration/2` 前重新校验 deferred 卷宗是否 stale / superseded
- [x] 将 `reconsideration_package.frozen_payload` 真正接入新复议 session 的上下文装配
- [x] 扩充 `frozen_payload`，冻结 `based_on_round`、基线事实、变化事实与变化分类
- [x] 让 `completeness_rule / inspection_rule / trigger_policy` 从“存档字段”升级为可执行规则
- [x] 在预览页展示 controversies 正文、基线/变化摘要与生命周期提示
- [x] 稳定 overview / indexes / adoption 回链，确保治理状态与对象关系可追索

因此，Phase 3 已经从“第一版闭环已可跑”进入“与 PRD 基本对齐”的状态；后续再做的，属于增强项而不是收口阻塞项。
