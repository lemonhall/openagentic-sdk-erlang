# 2026-03-07：Phase 1｜案卷与任务骨架实现对齐审计

## 文档状态
- 状态：实现审计基线 / 下一轮对齐施工前置文档
- 审计时间：2026-03-07
- 审计对象：当前仓库内已经落地的 Phase 1 相关实现
- 审计目标：确认当前实现与 `Phase 1` 设计稿之间，哪些已经对齐，哪些只落了一半，哪些仍未落地

---

## 1. 为什么需要这份文件
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-1-case-and-task-foundation.md` 已经给出 Phase 1 的目标、边界、DoD 与数据骨架。
- 当前代码实现已经明显不是“从零开始”，而是已经落下了第一版 `case -> round -> candidate -> task -> task_version` 骨架。
- 但现状并不是“设计稿已经完整落地”。如果不先做一次实现审计，直接继续开发，容易出现：
  - 把已经存在的能力重做一遍
  - 把设计稿里真正还没做的部分漏掉
  - 把 Phase 2/3/4 的能力误当成 Phase 1 缺口
  - 让文档、测试、代码再次漂移

因此，这份文件的作用不是替代设计稿，而是作为“设计稿与当前实现之间的对齐说明书”，供下一轮对齐施工直接引用。

---

## 2. 本文件与其他文件的引用关系

### 2.1 规范来源文件
本文件不重新定义产品与制度；凡属“应该做成什么样”，以以下文件为准：

1. Phase 1 直接施工基准：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-1-case-and-task-foundation.md`

2. 全局主线与对象背景：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`

3. 制度与机制约束：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-domain-mechanism-design.md`

4. 全量数据与 Schema 设计：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`

5. 汇总版 PRD：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-v1.md`

### 2.2 当前实现证据文件
本次审计主要以以下实现文件为证据：

- 核心存储与治理骨架：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`

- Web API：
  - `apps/openagentic_sdk/src/openagentic_web.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_cases_create.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_cases_overview.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_candidates_extract.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_candidates_approve.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_candidates_discard.erl`

- Web 页面与前端逻辑：
  - `apps/openagentic_sdk/priv/web/view/cases.html`
  - `apps/openagentic_sdk/priv/web/assets/case-governance.js`

- 测试证据：
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`

### 2.3 本文件与下一轮施工的关系
- 本文件是“对齐前置文档”，不是新的产品设计稿。
- 下一轮如果要开始“把实现与 Phase 1 设计稿对齐”，应先读：
  1. 当前文件
  2. `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-1-case-and-task-foundation.md`
  3. 相关实现与测试文件
- 下一轮实现计划应以“补齐差距”为目标，而不是推倒重做现有骨架。

---

## 3. 审计口径

### 3.1 判定等级
- `已对齐`：设计要求已有明确实现，并有代码与测试支撑。
- `部分对齐`：有占位或有一半实现，但还没有满足设计稿的完整语义。
- `未对齐`：设计稿明确要求，但当前代码没有对应实现，或只有极弱占位，无法视为落地。

### 3.2 本次审计聚焦范围
本次只审 Phase 1 范围内的内容，重点覆盖：
- Phase 1 的目标与 DoD
- Phase 1 直接涉及的对象模型与目录结构
- 模板起草与实例隔离
- 授权接驳分轨
- 候选任务审议会话与长期治理会话
- 案卷页、候选审批、内邮与基本 Web 体验

以下能力不作为“本轮必须缺口”处理：
- 真正的周期执行链路
- `monitoring_run` / `fact_report` / `inspection_review` 完整实现
- 观察包、复议卷宗、检察验卷
- Phase 2/3/4 主要能力

---

## 4. 当前总评

### 4.1 一句话判断
当前实现已经完成了 Phase 1 的“对象骨架 + 基础 Web 操作 + 基础测试闭环”，但还没有完整实现设计稿要求的“治理体验、授权接驳、模板制度、审计硬化”。

### 4.2 更准确的判断
如果只看最小骨架，当前实现已经具备：
- 从已完成朝议立案
- 自动抽取候选任务
- 候选任务进入待审流
- 候选任务废弃或生效
- 生效后生成正式任务与首个 `task_version`
- 候选审议会话直接转正为 `governance_session_id`

但如果按设计稿原文要求继续审：
- “聊天式审议”已具备治理页、任务详情页与同会话延续，但版本修订闭环仍未完整落地
- “模板库 / 模板起草流程”还没有落地
- “授权接驳分轨 / credential_binding 一等对象”已补上第一版，但仍未覆盖更完整的重授权机制
- “内邮系统”还只是候选待审通知的第一版，不是完整信箱模型
- “历史日志 / 对象注册表 / 乐观并发校验”还没有达到设计稿要求的硬化程度

因此，当前状态应定性为：

**Phase 1 核心骨架已实现，但仍需一轮明确的补齐式对齐。**

### 4.3 这份审计结论在施工层面到底意味着什么
为避免下一轮继续先“补齐审计认知”再开始编码，这里把结论直接翻译成施工语言：

- 已经可以视为“地基已成”的部分：
  - `workflow_session -> case -> round -> candidate -> task -> task_version` 主链路
  - 候选抽取、approve/discard、首版任务落盘、任务 workspace 初始化
  - `review_session_id -> governance_session_id` 直接转正逻辑
  - 案卷页、治理页、任务详情页这三张基础页面
  - 第一版 `credential_binding` 对象与任务激活前授权检查

- 下一轮必须围绕现有结构“长出来”的部分：
  - 治理会话里的版本修订闭环
  - 模板库 / 模板起草 / 模板实例化审计链
  - 授权重接驳、轮换与更细粒度审计
  - 统一信箱模型
  - `history.jsonl` / 对象注册表 / 乐观并发

- 下一轮不该误判的部分：
  - 不要把 Phase 2/3/4 的运行、检察、复议能力混入本轮缺口
  - 不要把“已有字段占位”误判为“制度已经落地”
  - 不要把“已有页面入口”误判为“完整产品闭环已经完成”

---

## 5. Phase 1 DoD 对齐检查

### 5.1 能从某轮朝议建立 `case`
- 判定：`已对齐`
- 设计来源：Phase 1 DoD、`case` 生命周期与立案责任
- 代码证据：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_cases_create.erl`
- 说明：
  - `create_case_from_round/2` 只接受来自 `workflow_session_id` 的立案输入。
  - 会先校验对应 workflow session 已完成，未完成则拒绝立案。
  - 立案时会同时生成 `case` 与 origin `deliberation_round`。

### 5.2 能抽取候选任务并进入待审流
- 判定：`已对齐`
- 设计来源：Phase 1 DoD、提案官职责、候选任务生命周期
- 代码证据：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
- 说明：
  - 当前实现支持立案后自动抽取，也支持后续手动重新抽取。
  - 候选对象会写入 `meta/candidates/`，并自动创建待审内邮。
  - 每个候选会生成一条独立 `review_session_id`。

### 5.3 能废弃或生效候选任务
- 判定：`已对齐`
- 设计来源：候选任务审议与“废弃 / 生效”动作
- 代码证据：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_candidates_approve.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_candidates_discard.erl`
- 说明：
  - 候选支持 `approve` 和 `discard` 两个主动作。
  - 内邮会在动作后被标记为已处理。

### 5.4 能为正式任务创建首个 `task_version`
- 判定：`已对齐`
- 设计来源：`monitoring_task` / `task_version` 对象关系
- 代码证据：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
- 说明：
  - 候选生效后会创建 `task.json` 与首个 `versions/<version_id>.json`。
  - `active_version_id` 会写回到 `task.links`。

### 5.5 能把候选任务审议会话直接转正为长期 `governance_session_id`
- 判定：`已对齐`
- 设计来源：`§55`、`§56`
- 代码证据：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
- 说明：
  - 当前实现没有为正式任务重开新的治理 session。
  - `review_session_id` 会直接写入 `monitoring_task.links.governance_session_id`。

### 5.6 Phase 1 DoD 总结
- 按最小 DoD 口径判断：当前实现 **已达成**。
- 但按设计稿更完整的“制度与体验”口径判断：当前实现 **尚未完全达成**。

---

## 6. 对象模型与数据落盘对齐情况

### 6.1 `case`
- 判定：`已对齐`
- 已落地内容：
  - 统一外壳 `header/links/spec/state/audit/ext`
  - `origin_round_id`
  - `origin_workflow_session_id`
  - `current_round_id`
  - `default_timezone`
  - `opening_brief`
  - `current_summary`
  - `status`
  - `phase`
  - `active_task_count`
- 对齐说明：
  - 新立案时 `phase = post_deliberation_extraction`
  - 当出现至少一个 `active` 任务时，会切换为 `monitoring_active`

### 6.2 `deliberation_round`
- 判定：`已对齐`
- 已落地内容：
  - `case_id`
  - `parent_round_id`
  - `workflow_session_id`
  - `triggering_briefing_id`
  - `resolution_id`
  - `round_index`
  - `kind`
  - `trigger_reason`
  - `starter_role`
  - `input_material_refs`
- 对齐说明：
  - 当前 Phase 1 范围内，它已经满足“origin round 归档对象”的基本要求。

### 6.3 `monitoring_candidate`
- 判定：`部分对齐`
- 已落地内容：
  - 有独立候选对象
  - 有 `review_session_id`
  - 有 `source_round_id`
  - 有候选级 `spec`
  - 有 `approved_task_id`
- 尚未完全对齐的点：
  - 设计稿建议的生命周期包含 `extracted -> inbox_pending -> under_review -> discarded/approved`。
  - 当前实现主要是 `inbox_pending -> approved/discarded`，`extracted` 与 `under_review` 没有独立状态建模。

### 6.4 `monitoring_task`
- 判定：`已对齐`
- 已落地内容：
  - `case_id`
  - `source_round_id`
  - `source_candidate_id`
  - `governance_session_id`
  - `active_version_id`
  - `workspace_ref`
  - `active_pack_ids`
  - `mission_statement`
  - `template_ref`
  - `credential_binding_refs` 占位
  - `health`
- 对齐说明：
  - 任务主对象目前保持的是“长期真相”，没有把版本内细节直接塞回 `task.json`。

### 6.5 `task_version`
- 判定：`已对齐`
- 已落地内容：
  - `case_id`
  - `task_id`
  - `previous_version_id`
  - `derived_from_template_ref`
  - `approved_by_op_id`
  - `objective`
  - `schedule_policy`
  - `report_contract`
  - `alert_rules`
  - `source_strategy`
  - `tool_profile`
  - `credential_requirements`
  - `autonomy_policy`
  - `promotion_policy`
- 对齐说明：
  - `schedule_policy` 和 `tool_profile` 当前都是版本内嵌值对象，符合 Phase 1 设计意图。

### 6.6 目录布局与落盘方式
- 判定：`部分对齐`
- 已落地内容：
  - `cases/<case_id>/meta/`
  - `cases/<case_id>/artifacts/`
  - `cases/<case_id>/workspaces/`
  - `cases/<case_id>/published/`
  - `meta/rounds/`
  - `meta/tasks/<task_id>/task.json`
  - `meta/tasks/<task_id>/versions/<version_id>.json`
  - `meta/mail/`
  - `meta/indexes/`
- 尚未完全对齐的点：
  - 当前没有 `history.jsonl` 轻量历史日志层。
  - 当前没有显式对象类型注册表。
  - 当前虽然有 `revision` 字段和原子替换写盘，但没有实现设计稿要求的乐观并发校验语义。

### 6.7 当前已经形成的“主真相路径”
这条路径已经可以当作下一轮施工时的默认认知，不需要再重新梳理：

1. `workflow_session` 作为立案来源真相
2. `case` 作为长期治理主对象
3. `deliberation_round` 作为正式朝议与触发来源归档
4. `monitoring_candidate` 作为候选任务待审对象，并拥有独立 `review_session_id`
5. `monitoring_task` 作为长期任务真相对象，并沿用 `governance_session_id`
6. `task_version` 作为冻结版执行定义
7. `workspaces/<task_id>/TASK.md` 作为任务私有实例工作区起点
8. `credential_bindings/` 作为任务级授权接驳对象目录
9. `meta/mail/` 与 `meta/indexes/` 作为第一版通知与派生索引层

下一轮如果需要加新能力，应优先判断“这项能力应该挂到这条真相路径的哪一层”，而不是先新造平行对象。

---

## 7. Web 与治理体验对齐情况

### 7.1 案卷页与基础操作
- 判定：`已对齐`
- 已落地内容：
  - 立案页
  - 案卷总览
  - 候选列表
  - 正式任务列表
  - 内邮列表
  - 手动重新抽取候选
  - 在页内直接 approve / discard

### 7.2 聊天式审议页
- 判定：`部分对齐`
- 设计要求：
  - 候选任务或正式任务应进入“与专属官员的聊天式治理界面”
  - 候选审议、生效、整改、版本化修订，应围绕治理会话沉淀
- 当前现状：
  - 现已新增 `view/governance-session.html`，可围绕 `review_session_id` / `governance_session_id` 打开聊天式治理界面
  - 现已新增 `POST /api/sessions/:sid/query`，可在既有 session 上原地续聊，并继续使用 `GET /api/sessions/:sid/events` 观察事件流
  - 案卷页中的 candidate / task 已出现治理入口，不再只是列表 + 固定 payload 按钮
  - 但仍缺少围绕版本修订、任务详情、整改闭环的一体化治理面

### 7.3 右上角信箱与统一信箱体验
- 判定：`未对齐`
- 设计要求：
  - Web 右上角统一信箱提醒
  - 支持待审、异常、可复议、急报等统一消息入口
- 当前现状：
  - 只有案卷页内的 `mailList`
  - 还不是全站统一信箱模型
  - 还没有右上角提醒与全局跳转体验

### 7.4 任务详情页
- 判定：`已对齐`
- 设计要求：
  - 至少包含任务定义、版本历史、运行记录、交付物、授权状态、治理入口
- 当前现状：
  - 现已新增 `view/task-detail.html`
  - 现已新增 `GET /api/cases/:case_id/tasks/:task_id/detail`
  - 页面已能展示任务定义、版本历史、运行记录空态、交付物空态、授权状态与治理入口

### 7.5 当前 Web 体验的真实边界线
为了防止下一轮误把“已有页面”理解为“页面能力已经闭环”，这里明确边界：

- 已经具备：
  - `cases.html`：立案、总览、候选审批、任务入口、案卷内邮
  - `governance-session.html`：围绕既有 session 继续发治理指令并观察事件流
  - `task-detail.html`：查看任务定义、版本列表、授权状态、治理入口、运行/交付物空态

- 仍未具备：
  - 全站统一信箱入口与右上角未读提醒
  - 在治理页内直接发起“生成新版本 / 版本差异对比 / 整改后再激活”的一体化流转
  - 真实非空的运行记录、交付物列表与基于它们触发的进一步治理动作

---

## 8. 制度层面尚未对齐的关键缺口

### 8.1 模板库、实例化与模板起草流程
- 判定：`部分对齐`
- 已有部分：
  - `template_ref` 已进入 candidate/task/task_version 数据结构
  - 任务 workspace 是独立的，符合“实例不共享执行体”原则
- 缺失部分：
  - 没有 `task_template_library` 或模板对象集合
  - 没有模板起草、模板引用、模板实例化审计链
  - 目前只是数据字段占位，不足以称为“模板制度落地”

### 8.2 授权接驳分轨与 `credential_binding`
- 判定：`部分对齐`
- 已有部分：
  - `credential_requirements`
  - `credential_binding_refs`
  - 独立 `credential_binding` 对象
  - `material_ref` 指向敏感材料本体的引用机制
  - `awaiting_credentials`、`ready_to_activate`、`credential_expired` 状态流
  - `POST /api/cases/:case_id/tasks/:task_id/credential-bindings` 与 `POST /api/cases/:case_id/tasks/:task_id/activate`
- 仍待补齐：
  - 更完整的 `reauthorization_required` / 轮换补录机制
  - 真正受控的敏感材料安全区与更细粒度接驳审计

### 8.3 候选任务治理会话沉淀
- 判定：`部分对齐`
- 已有部分：
  - 有 `review_session_id`
  - 有“候选转正即沿用会话”的元数据逻辑
  - 现已可围绕该 session 直接打开 Web 治理页并继续对话
  - 现已可通过任务详情页查看版本历史、授权状态并回到同一条治理会话
- 缺失部分：
  - 没有“继续围绕同一条长期治理线修订版本”的产品体验闭环

### 8.4 内邮系统
- 判定：`部分对齐`
- 已有部分：
  - 候选待审内邮
  - `message_type`
  - `related_object_refs`
  - `severity`
  - `available_actions`
  - `mail-unread.json` 派生索引
- 缺失部分：
  - 没有 `已读 / 归档` 状态模型
  - 没有按类型筛选
  - 没有统一全站信箱
  - 没有异常督办 / 可复议 / 急报消息类型的落地

### 8.5 审计硬化
- 判定：`未对齐`
- 已有部分：
  - 元数据对象统一 `revision`
  - 写盘使用临时文件 + rename 的原子替换模式
  - 有基础派生索引
- 缺失部分：
  - 无 `history.jsonl`
  - 无对象类型注册表
  - 无乐观并发校验协议

### 8.6 明确不应误记为“已经实现”的语义
以下项目在下一轮讨论时，必须明确视为“尚未完整落地”，避免无效争论：

- `template_ref` 已存在，不等于模板库、模板起草流程、模板实例化制度已存在。
- `mail-unread.json` 已存在，不等于统一信箱模型、已读归档、全站提醒已存在。
- `governance-session.html` 已存在，不等于围绕同一治理线的版本修订闭环已存在。
- `task-detail.html` 已存在，不等于真实运行历史、真实交付物治理链已经存在。
- `revision` 已存在，不等于乐观并发写入协议已经存在。
- `credential_binding` 已存在，不等于轮换、失效补录、重授权全流程已经存在。

---

## 9. 当前实现可直接复用、不要重做的部分

下一轮对齐时，以下内容应直接复用并在其上补齐，不建议推倒重做：

1. `openagentic_case_store.erl` 中已经建立的核心对象与目录骨架
2. `case` / `deliberation_round` / `monitoring_task` / `task_version` 的基础 schema
3. 立案、抽取、approve、discard、overview 这组基础 API
4. `review_session_id -> governance_session_id` 的直接转正逻辑
5. `workspaces/<task_id>/TASK.md` 的实例级 workspace 起点
6. `meta/indexes/` 的第一版索引思路
7. 现有 EUnit 与 Web API 测试骨架

这些内容已经构成了 Phase 1 的“第一版可运行骨架”，下一轮应在此基础上做补齐，而不是重新发明一套平行结构。

---

## 10. 下一轮对齐建议顺序

建议下一轮按以下顺序推进，收益最高，也最不容易返工：

### 10.1 第一优先级：治理会话真正落地
- 为 candidate/task 增加真正的治理会话入口
- 让 `review_session_id` / `governance_session_id` 不只是元数据，而是可打开、可继续对话的治理面
- 把“聊天式审议”从设计语义变成产品语义

### 10.2 第二优先级：授权接驳分轨
- 已补上第一版 `credential_binding` 一等对象与任务授权状态流
- 下一步聚焦重授权、轮换与更强审计边界

### 10.3 第三优先级：模板制度补齐
- 引入模板库与模板引用关系
- 明确模板只用于起草与参考实现，不共享正式执行体
- 把目前的 `template_ref` 从占位升级为真正制度对象

### 10.4 第四优先级：审计与存储硬化
- 增加 `history.jsonl`
- 增加对象类型注册表
- 增加乐观并发写入校验

### 10.5 第五优先级：内邮信箱体验补齐
- 做成统一信箱入口
- 补 `已读 / 归档 / 筛选`
- 为后续异常督办、急报、可复议通知预留统一模型

### 10.6 下一轮直接文件落点（按缺口分组）
为避免下一轮先花时间重新定位代码入口，这里直接给出推荐落点：

- 治理会话闭环：
  - 重点先看 `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - Web 路由与 handler 主要看 `apps/openagentic_sdk/src/openagentic_web.erl`、`apps/openagentic_sdk/src/openagentic_web_api_sessions_query.erl`
  - 页面与交互主要看 `apps/openagentic_sdk/priv/web/view/governance-session.html`、`apps/openagentic_sdk/priv/web/assets/governance-session.js`、`apps/openagentic_sdk/priv/web/view/task-detail.html`、`apps/openagentic_sdk/priv/web/assets/task-detail.js`
  - 回归测试主要加在 `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`

- 模板制度：
  - 现阶段模板相关字段都从 `apps/openagentic_sdk/src/openagentic_case_store.erl` 进入对象图
  - 若需把模板库做成独立对象，应新增同家族存储模块，不要把模板制度直接堆进 Web handler
  - 回归测试仍应以 `apps/openagentic_sdk/test/openagentic_case_store_test.erl` 为主入口

- 授权接驳分轨：
  - 重点文件是 `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - Web 层配套是 `apps/openagentic_sdk/src/openagentic_web_api_task_credential_bindings.erl` 与 `apps/openagentic_sdk/src/openagentic_web_api_tasks_activate.erl`
  - 页面配套是 `apps/openagentic_sdk/priv/web/assets/task-detail.js`
  - 测试入口是 `apps/openagentic_sdk/test/openagentic_case_store_test.erl` 与 `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`

- 统一信箱与消息模型：
  - 当前案卷页入口在 `apps/openagentic_sdk/priv/web/view/cases.html` 与 `apps/openagentic_sdk/priv/web/assets/case-governance.js`
  - 路由总入口在 `apps/openagentic_sdk/src/openagentic_web.erl`
  - 底层消息与索引仍先落在 `apps/openagentic_sdk/src/openagentic_case_store.erl`

- 审计硬化：
  - 先在 `apps/openagentic_sdk/src/openagentic_case_store.erl` 补 `history.jsonl`、对象注册表、并发写入协议
  - 再用 `apps/openagentic_sdk/test/openagentic_case_store_test.erl` 做对象级回归

### 10.7 如果下一轮被定义为“Phase 1 对齐收口轮”，完成即停判据
下一轮不应再以“感觉差不多”收尾；如果目标是把 Phase 1 真正收口，至少应满足以下判据：

1. 能围绕同一条 `governance_session_id` 对正式任务继续治理，并形成新的 `task_version` 或明确的版本修订动作沉淀。
2. 模板库不再只是 `template_ref` 字段占位，而是具备模板对象、引用关系和实例化审计链。
3. `credential_binding` 不再只支持首次接驳，还支持至少一版明确的失效补录 / 重授权语义。
4. Web 侧出现统一信箱入口，而不再仅有案卷页内的 `mailList`。
5. 底层落盘补上 `history.jsonl`、对象类型注册表与乐观并发校验中的至少最小闭环。
6. `rebar3 eunit` 继续通过，且新增能力有对应 EUnit / Web API 测试覆盖。

---

## 11. 验证结论

本次审计基于以下实际验证：

- 命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit`
- 时间：2026-03-07
- 结果：`187 tests, 0 failures`
- 补充说明：当前命令尾部还会额外打印一段与 `otp_release` eval 相关的噪音输出，但 `LASTEXITCODE = 0`；本次审计按测试结果成功处理，不把这段尾噪误判为 Phase 1 缺口。

这说明当前 Phase 1 已落地骨架在仓内是稳定可测的；但“测试通过”不等于“已完全对齐设计稿”。

本文件的结论仍然是：

**当前实现已经具备 Phase 1 主干，且已补上任务详情页与第一版授权接驳分轨；剩余主要缺口集中在模板制度、信箱统一模型与审计硬化。**

---

## 12. 给下一轮实现者的直接指令
- 不要重做 `case` 主骨架。
- 不要重做基础 API。
- 把当前实现视为“已完成第一层地基”。
- 下一轮的核心任务不是“从零设计”，而是“把设计稿里已经明确写出的剩余制度与体验补齐”。
- 开工前先同时阅读：
  - 当前文件
  - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-1-case-and-task-foundation.md`
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`

这样才能避免“以为没做，其实已经做了”和“以为做完了，其实只做了一半”这两种常见返工。

---

## 13. 能力-结论-证据速查表

| 能力项 | 当前判定 | 直接证据 |
| --- | --- | --- |
| 从已完成 workflow session 立案 | 已对齐 | `openagentic_case_store.erl`、`openagentic_web_api_cases_create.erl`、`openagentic_case_store_test.erl` |
| 自动 / 手动抽取候选任务 | 已对齐 | `openagentic_case_store.erl`、`openagentic_case_store_test.erl` |
| approve / discard 候选 | 已对齐 | `openagentic_web_api_candidates_approve.erl`、`openagentic_web_api_candidates_discard.erl`、相关 EUnit |
| 候选转正式任务并生成首版 `task_version` | 已对齐 | `openagentic_case_store.erl`、`openagentic_case_store_test.erl` |
| `review_session_id -> governance_session_id` 转正 | 已对齐 | `openagentic_case_store.erl`、`openagentic_case_store_test.erl` |
| 聊天式治理页入口 | 部分对齐 | `view/governance-session.html`、`governance-session.js`、`openagentic_web_api_sessions_query.erl` |
| 任务详情页 | 已对齐 | `view/task-detail.html`、`task-detail.js`、`openagentic_web_api_tasks_detail.erl` |
| 任务授权接驳第一版 | 部分对齐 | `openagentic_case_store.erl`、`openagentic_web_api_task_credential_bindings.erl`、`openagentic_web_api_tasks_activate.erl` |
| 模板制度 | 部分对齐 | 仅有 `template_ref` / `derived_from_template_ref` 字段，占位多于制度 |
| 统一信箱模型 | 未对齐 | 当前仅 `cases.html` 内 `mailList` 与 `mail-unread.json` |
| 审计硬化 | 未对齐 | 仅有 `revision` 与原子写盘，无 `history.jsonl` / 注册表 / 乐观并发 |

这个表的用处只有一个：下一轮先扫这一节，再决定开工顺序；不要再重复做一轮“到底哪些已经有了”的认知体操。
