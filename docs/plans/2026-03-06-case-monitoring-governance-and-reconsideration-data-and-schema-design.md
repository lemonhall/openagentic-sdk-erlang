# 2026-03-06：朝议后专项监测、督办与复议系统（数据与 Schema 设计）

## 文档状态
- 状态：从总草案拆出的数据与 Schema 文档（保信息版）
- 来源：`docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-v1.md`
- 对应原稿章节：§§37-84
- 说明：本次拆分以章节迁移为主，保留目录布局、落盘规则、session 分层、operation/timeline 与最小 schema 细节
- 配套：产品主线见 `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`；制度设计见 `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-domain-mechanism-design.md`

---

## 37. 数据落盘总原则：三层分离
### 37.1 三层存储
本系统的落盘应明确分为三层：
- 治理元数据层：`case`、`deliberation_round`、`monitoring_task`、`task_version`、`observation_pack`、`reconsideration_package`、`internal_mail` 等对象
- 会话事件层：继续沿用现有 `session/meta.json + events.jsonl`，用于朝会 session、任务治理会话、每次 `monitoring_run` / `run_attempt` 的执行 transcript
- 产物与工作区层：脚本、缓存、报告、截图、CSV、附件、resolution 三件套、fact_report 三件套等重资产材料

### 37.2 分层职责
- 元数据层负责对象状态、引用关系与治理流转
- 事件层负责可追溯 transcript
- 文件层负责长期工作区与正式交付物

### 37.3 原则
不能把所有东西都硬塞进 `workflow_session/events.jsonl`；制度对象、会话事件、重资产文件必须分层。

---

## 38. 目录布局：以 `case` 为根，`sessions` 独立保留
### 38.1 根目录原则
v1 继续坚持 local-first 文件系统落盘。新系统的正式对象与材料应以 `cases/<case_id>/...` 为主根目录，而现有 `sessions/<session_id>/...` 继续单独保留为事件会话层。

### 38.2 两大根目录职责
- `cases/`：制度对象、正式材料、任务 workspace、共享发布区
- `sessions/`：朝会 session、治理会话、执行 transcript

### 38.3 设计意义
这样产品顶层对象与磁盘顶层对象保持一致：先看到案卷，再看到它下面的轮次、任务、观察包和卷宗包。

---

## 39. `cases/<case_id>/` 的一级结构
### 39.1 建议一级目录
每个 `case` 目录下建议先固定四类一级结构：
- `meta/`：结构化元数据
- `artifacts/`：正式归档材料
- `workspaces/`：各任务私有长期 workspace
- `published/`：正式发布给本案可引用的共享材料区

### 39.2 设计边界
`published/` 必须单独存在，不能简单把 `artifacts/` 全量暴露为共享区。因为“已归档”不等于“可供同案其他任务直接引用”。

---

## 40. `meta/` 采用一对象一文件 / 一目录树
### 40.1 组织方式
`meta/` 不应做成全局大 JSON 仓库，而应按对象类型拆目录。建议结构例如：
- `meta/case.json`
- `meta/rounds/<round_id>.json`
- `meta/tasks/<task_id>/task.json`
- `meta/tasks/<task_id>/versions/<version_id>.json`
- `meta/tasks/<task_id>/runs/<run_id>.json`
- `meta/packs/<pack_id>.json`
- `meta/briefings/<briefing_id>.json`
- `meta/mail/<message_id>.json`

### 40.2 原则
v1 应坚持“一对象一文件 / 一目录树”的方式，索引可以存在，但索引不是真相源。

---

## 41. 内部 ID 与人类可读名称分离
### 41.1 原则
目录和对象引用链一律使用稳定内部 ID；所有人类可读名称只作为对象属性存在，不参与真相引用。

### 41.2 对象建议属性
每个对象可保留：
- `title`
- `short_name`
- `slug`
- `display_code`

### 41.3 设计意义
这样可以安全重命名、支持同题不同变体，并避免路径碰撞和引用断裂。

---

## 42. 对象关系一律使用显式 ID 引用
### 42.1 引用原则
对象之间的关系应全部基于显式 ID 字段表达，例如：
- `case_id`
- `task_id`
- `round_id`
- `run_id`
- `pack_id`
- `briefing_id`

### 42.2 路径的地位
文件路径只作为派生定位手段，不作为主引用语义。真正的业务语义应以对象 ID 为真相源。

---

## 43. 元数据对象统一公共头字段
### 43.1 公共头字段
所有元数据对象都应带统一公共头，至少包括：
- `id`
- `type`
- `schema_version`
- `created_at`
- `updated_at`
- `status`
- `title`
- `case_id`（如果对象属于某个 case）
- `source_round_id`（如果对象源于某轮朝议）
- `labels`（可选）
- `ext`

### 43.2 原则
每种对象可以叠加自己的专属字段，但公共头必须统一，避免各写各的 JSON 风格。

---

## 44. 对象类型注册表
### 44.1 必要性
随着对象类型增多，v1 应从一开始就有一份显式的对象类型注册表，哪怕最开始只是一个简单的静态定义文件。

### 44.2 注册表至少回答
- 对象类型名是什么
- 文件位置规则是什么
- 主键字段是什么
- 默认状态字段是什么
- 是否属于某个 `case`
- 是否有独立 artifact 目录
- 是否关联 session

---

## 45. 写入策略：当前快照 + 轻量历史日志
### 45.1 折中写法
v1 的元数据层采用“当前快照文件 + 轻量历史日志”的折中写法，而不是纯重写无历史，也不是一上来全量 event sourcing。

### 45.2 典型结构
例如：
- `task.json`：当前真相快照
- `history.jsonl`：轻量变更历史

### 45.3 适用对象
关键对象如 `task`、`briefing`、`pack`、`mail`、`operation` 都建议采用此模式。

---

## 46. 派生索引层：可重建，但不是真相源
### 46.1 设计原则
v1 应引入 `case` 级派生索引文件来加速 Web 查询，但这些索引必须是可重建的辅助层，而不是真相源。

### 46.2 示例索引
例如：
- `meta/indexes/tasks-by-status.json`
- `meta/indexes/packs-active.json`
- `meta/indexes/briefings-latest.json`
- `meta/indexes/mail-unread.json`

### 46.3 原则
索引可以过期，可以修复，可以重建，但不能成为唯一真相源。

---

## 47. 并发写入：`revision` + 乐观并发 + 原子替换
### 47.1 基本规则
每个元数据对象都应带 `revision` 字段。写入时采用：
- 对象 `revision`
- 乐观并发校验
- 原子替换写盘

### 47.2 设计意义
这样可避免多方同时改同一对象时出现后写覆盖前写、状态倒退、快照与历史不一致等问题。

---

## 48. 跨对象更新：显式 `operation`，不假装有数据库事务
### 48.1 基本原则
跨多个对象的业务动作，不追求假的跨文件强事务，而采用：
- 显式 operation 记录
- 幂等更新
- 派生层后补

### 48.2 典型动作
例如：
- `activate_task`
- `defer_briefing`
- `start_reconsideration`

### 48.3 动作状态
`operation` 至少应有：
- `pending`
- `applied`
- `partially_applied`
- `failed`

---

## 49. `operation` 作为一等对象落盘
### 49.1 落盘位置
每个关键跨对象动作都应在 `case` 下有正式记录，例如：
- `cases/<case_id>/meta/ops/<op_id>.json`
- 必要时配 `history.jsonl`

### 49.2 建议字段
至少记录：
- `op_id`
- `op_type`
- `case_id`
- `initiator`
- `target_ids`
- `status`
- `created_at`
- `updated_at`
- `applied_steps`
- `failed_steps`
- `retry_count`

---

## 50. `case` 级统一时间线：聚合视图，不是真相源
### 50.1 总时间线
每个 `case` 都应维护一条 append-only 的统一时间线，用于案卷级浏览与复盘，例如：
- `cases/<case_id>/meta/timeline.jsonl`

### 50.2 作用
它用于展示案卷编年史，例如：
- 某轮朝会完成
- 某候选任务生成 / 生效 / 废弃
- 某急报触发
- 某卷宗被 `deferred`
- 某次复议正式开启

### 50.3 原则
timeline 是聚合视图，不是真相源。真相仍在对象快照、history、operation 和 session 中。

---

## 51. 时间线只收里程碑事件
### 51.1 边界
`case` 级统一时间线只记录里程碑事件，不记录所有底层细粒度运行明细；细明细继续留在对象 history、operation 和 session transcript 中。

### 51.2 典型里程碑
例如：
- 某轮朝会完成
- 某候选任务生成 / 生效 / 废弃
- 某任务进入待整顿
- 某观察包 ready
- 某卷宗 deferred / superseded / consumed
- 某轮复议开启并结束

---

## 52. 时间线事件统一外壳
### 52.1 公共字段
每条 `timeline.jsonl` 里的事件都应使用统一外壳，至少包含：
- `event_id`
- `event_type`
- `case_id`
- `created_at`
- `severity`
- `summary`
- `actor`
- `related_object_refs`
- `op_id`（如由某次 operation 触发）
- `session_id`（如与某个 session 相关）
- `ext`

### 52.2 原则
`summary` 应始终是可直接给人看的一句话；对象关联继续使用 ID 引用。

---

## 53. 时间线写入是派生性的，不阻塞主流程
### 53.1 工程语义
`timeline` 的写入应当是派生性的、可补写的，不应因为时间线追加失败而阻断主业务动作成功。

### 53.2 顺序建议
1. 先写主对象真相
2. 再 best-effort 追加 timeline
3. 失败时记录修复信号，后续重放补齐

---

## 54. 只有三类对象默认拥有独立 session
### 54.1 默认拥有 session 的对象
v1 默认只让以下三类对象拥有独立 session：
- `deliberation_round`：`workflow_session_id`
- `monitoring_task`：`governance_session_id`
- `run_attempt`：`execution_session_id`

### 54.2 默认不单独建 session 的对象
以下对象默认不创建独立 session：
- `observation_pack`
- `reconsideration_package`
- `internal_mail`
- `deliberation_resolution`
- `inspection_review`

### 54.3 原则
不是每个对象都应该有自己的 session。只有真正承载“对话 / 执行过程”的对象才应拥有 session。

---

## 55. `monitoring_task` 的治理会话是长期单线
### 55.1 基本原则
每个 `monitoring_task` 应当只有一条长期 `governance_session_id`，跨多个版本持续存在。

### 55.2 运行时上下文装配
继续对话时，默认不全量重放整个治理 transcript，而优先装配：
- 当前 `task.json`
- 当前生效 `task_version`
- 历史版本摘要
- 最近一段治理对话
- 上次整改结论或异常摘要

### 55.3 设计意义
这样既保住“始终在和同一个下臣聊同一份差事”的体验，又控制了上下文膨胀。

---

## 56. 候选任务审议会话直接转正为治理会话
### 56.1 基本原则
候选任务阶段的审议会话，在任务生效后，应直接转正为该任务的长期 `governance_session_id`，而不是重新开一条新的治理会话。

### 56.2 设计意义
这样可保留：
- 任务最初是如何被讨论出来的
- 生效时的澄清过程
- 后续整改与改版的连续历史

---

## 57. `monitoring_run` 是业务轮次，重试建模为 `run_attempt`
### 57.1 分层模型
`monitoring_run` 表示“业务上的一次监测轮次”；重试 / 恢复 / 再执行，不应算新的 run，而应建模为其下属的 `run_attempt`。

### 57.2 `run_attempt`
每个 `attempt` 都拥有自己的 `execution_session_id`，用于记录本次尝试的独立执行 transcript。

### 57.3 设计意义
这样可以清楚区分：
- 这轮差本来就该办一次
- 为了办成这次差，系统实际试了几次

---

## 58. 长期 `task workspace` 与 `attempt scratch` 分离
### 58.1 长期空间
`task workspace` 用于长期积累：
- 脚本
- 配置
- 缓存
- 登录态
- 稳定方法实现

### 58.2 尝试级 scratch
每个 `run_attempt` 都应拥有自己的独立 scratch 工作目录，用于存放：
- 本次抓取原始结果
- 临时日志
- 本次截图
- 临时下载文件
- 本次调试输出

### 58.3 原则
默认临时产物先落在 attempt scratch 中，而不是把所有执行残留都直接写进长期 `task workspace`。

---

## 59. attempt 产物需显式提升，才能成为 run 正式交付物
### 59.1 候选产物 vs 正式成果
`attempt scratch` 中的文件默认只是候选产物；只有经过明确“提升（promote）”后，才能成为 `monitoring_run` 级正式交付物。

### 59.2 典型正式成果
例如：
- 最终 `report.md`
- 最终 `facts.json`
- 最终 `artifacts.json`
- 被认定为有效证据的截图、CSV、原始抓取样本

### 59.3 原则
失败 attempt 的 scratch 应保留可追溯性，但默认不进入“正式上卷材料”。

---

## 60. 核心对象采用统一外壳 schema
### 60.1 统一顶层结构
v1 的核心对象 JSON 应统一采用以下外壳结构：
- `header`
- `links`
- `spec`
- `state`
- `audit`
- `ext`

### 60.2 各层职责
- `header`：通用头字段，如 `id`、`type`、`schema_version`、`created_at`、`updated_at`、`revision`
- `links`：对象关系，如 `case_id`、`round_id`、`task_id`、`pack_id`、`session_id`、`op_id`
- `spec`：相对稳定、意图性的定义内容
- `state`：当前状态、活动指针、进度与生命周期信息
- `audit`：最近变更摘要、来源、触发者、reason 等审计辅助信息
- `ext`：预留扩展位

### 60.3 原则
所有核心对象都应遵守这套统一外壳，而不是每种对象各自自由发挥顶层 JSON 结构。

---

## 61. `case` 的最小 schema
### 61.1 `case` 要回答的问题
`case` 的最小 schema 应回答：
- 这案子是什么
- 它从哪来
- 它现在处于什么阶段
- 当前应关注哪几个下级对象

### 61.2 建议结构
- `header`
- `links`：如 `origin_round_id`、`origin_workflow_session_id`、`current_round_id`、`latest_briefing_id`、`active_pack_ids`
- `spec`：如 `title`、`display_code`、`topic`、`owner`、`default_timezone`、`labels`、`opening_brief`
- `state`：如 `status`、`current_summary`、`active_task_count`、`active_pack_count`
- `audit` / `ext`

### 61.3 两类摘要必须分离
`case` 必须同时保留：
- `opening_brief`：立案时的原始案由，尽量不改
- `current_summary`：随着轮次推进不断更新的当前案情摘要

---

## 62. `case` 显式拥有 `phase`
### 62.1 原则
`case` 除了生命周期层面的 `status` 外，还应显式拥有一个 `phase` 字段，用于表达“当前主要处于哪种治理阶段”。

### 62.2 示例阶段
可参考：
- `post_deliberation_extraction`
- `monitoring_active`
- `briefing_ready`
- `briefing_deferred`
- `reconsideration_in_progress`
- `awaiting_new_signals`
- `closed`

---

## 63. `deliberation_round` 的最小 schema
### 63.1 `deliberation_round` 要回答的问题
它应回答：
- 这一次正式朝会是什么
- 由什么触发
- 实际吃了哪些材料
- 产出了什么正式结论文书

### 63.2 建议结构
- `header`
- `links`：`case_id`、`parent_round_id`、`workflow_session_id`、`triggering_briefing_id`、`resolution_id`
- `spec`：`round_index`、`kind`、`trigger_reason`、`starter_role`、`input_material_refs`
- `state`：`status`、`phase`、`started_at`、`ended_at`
- `audit`

### 63.3 关键要求
`deliberation_round` 应显式记录 `triggering_briefing_id` 和 `input_material_refs`，用于审计“这一轮朝会到底吃了哪些卷宗和材料”。

---

## 64. `monitoring_task` 的最小 schema
### 64.1 `monitoring_task` 要回答的问题
它应回答：
- 这份差事是什么
- 它现在是否有效
- 当前该按哪个版本执行
- 它依附于哪个治理会话与 workspace
- 它当前健康不健康

### 64.2 建议结构
- `header`
- `links`：`case_id`、`source_round_id`、`source_candidate_id`、`governance_session_id`、`active_version_id`、`workspace_ref`、`active_pack_ids`
- `spec`：`title`、`display_code`、`mission_statement`、`default_timezone`、`schedule_policy_ref`、`template_ref`、`credential_binding_refs`
- `state`：`status`、`health`、`latest_run_id`、`latest_successful_run_id`、`last_report_at`
- `audit` / `ext`

### 64.3 任务级长期真相
`monitoring_task` 中只放“任务级长期真相”，不要把具体执行细节和版本细节塞进任务主对象。

---

## 65. `mission_statement` 属于 `task`，细则下沉到 `task_version`
### 65.1 原则
`monitoring_task` 中应有一个简洁但正式的 `mission_statement`，作为这份差事的长期“使命定义”。

### 65.2 边界
更细的执行规则、阈值、交付物细则，应下沉到 `task_version`。

---

## 66. `task_version` 的最小 schema
### 66.1 `task_version` 要回答的问题
`task_version` 应回答：“在这一版里，这份差具体怎么做。”

### 66.2 建议结构
- `header`
- `links`：`case_id`、`task_id`、`previous_version_id`、`derived_from_template_ref`、`approved_by_op_id`
- `spec`：`objective`、`schedule_policy`、`report_contract`、`alert_rules`、`source_strategy`、`tool_profile`、`credential_requirements`、`autonomy_policy`、`promotion_policy`
- `state`：`status`、`activated_at`、`superseded_at`
- `audit`：`change_summary`、`approval_summary`

### 66.3 不可变原则
`task_version` 一旦进入 `active`，就应视为不可变；任何定义层变更都必须创建新的版本，而不是回改旧版本。

---

## 67. `report_contract` 必须显式存在于 `task_version.spec`
### 67.1 原则
`task_version.spec` 必须显式包含 `report_contract`，把“这版差事应交什么卷”正式写死，而不是默会约定。

### 67.2 作用
它用于规定：
- 本版任务必须交哪些正式产物
- 每种产物的最小结构要求
- 哪些字段是必须的
- 什么情况下可判定“交卷不合格”

---

## 68. `report_contract` 采用统一底线 + 任务扩展
### 68.1 系统底线
系统级最低交卷底线至少包括：
- `report.md`
- `facts.json`
- `artifacts.json`
- `facts.json` 满足统一骨架
- `artifacts.json` 能定位正式附件
- 至少有一个可追溯来源引用

### 68.2 任务扩展
每个 `task_version.report_contract` 可在底线之上增加自己的扩展要求，但不能低于底线。

---

## 69. `observation_pack` 的最小 schema
### 69.1 `observation_pack` 要回答的问题
它应回答：
- 这包材料是为了回答什么问题
- 它要求哪几份监测任务一起交卷
- 什么情况下算 ready
- 当前离 ready 还有多远

### 69.2 建议结构
- `header`
- `links`：`case_id`、`source_round_id`、`latest_briefing_id`、`current_inspection_review_id`
- `spec`：`title`、`target_question`、`task_bindings`、`freshness_window`、`completeness_rule`、`inspection_rule`、`trigger_policy`
- `state`：`status`、`ready_score`、`missing_requirements`、`latest_ready_at`、`latest_deferred_briefing_id`

### 69.3 `task_bindings`
`observation_pack` 不应只保存一个平面的 `task_ids` 列表，而应显式保存 `task_bindings`，至少表达：
- `task_id`
- `role`
- `required`
- `freshness_requirement`
- `notes`

---

## 70. `ready_score` 是辅助信号，不是裁决字段
### 70.1 定位
`ready_score` 只能是 UI / 督办辅助信号，不能取代正式的 readiness 规则与检察结论。

### 70.2 真正裁决来源
真正决定 `ready_for_reconsideration` 的，仍应是：
- freshness 是否满足
- completeness_rule 是否满足
- inspection_review 是否通过
- 是否存在阻断性争议 / 缺件

---

## 71. `inspection_review` 的最小 schema
### 71.1 `inspection_review` 要回答的问题
它应回答：
- 检察官审的是哪一个观察包、哪一批材料
- 结论是什么
- 缺什么、争什么、风险点在哪
- 这份检察结果是否已经被某版卷宗包采用

### 71.2 建议结构
- `header`
- `links`：`case_id`、`pack_id`、`reviewed_run_ids`、`reviewed_report_ids`、`derived_briefing_id`
- `spec`：`review_scope`、`checklist`、`applied_rules`、`controversy_candidates`
- `state`：`status`、`decision`、`blocking_issues`、`missing_items`、`quality_notes`、`confidence_notes`
- `audit` / `ext`

### 71.3 快照原则
`inspection_review` 应是一份次次留痕的独立检察快照对象，而不是挂在 `observation_pack` 上被不断原地改写的单一状态块。

---

## 72. `reconsideration_package` 的最小 schema
### 72.1 `reconsideration_package` 要回答的问题
它应回答：
- 属于哪个 `case`、哪个 `observation_pack`
- 基于哪次检察、哪轮上次结论、哪些报告材料
- 当前状态是什么
- 冻结内容到底是什么
- 最终有没有触发新一轮复议

### 72.2 建议结构
- `header`
- `links`：`case_id`、`pack_id`、`based_on_round_id`、`source_inspection_review_id`、`supersedes_briefing_id`、`consumed_by_round_id`
- `spec`：`trigger_reason`、`included_report_refs`、`included_resolution_ref`、`included_urgent_refs`、`included_controversy_refs`
- `state`：`status`、`freshness_checked_at`、`stale_reason`、`display_code`

### 72.3 冻结快照原则
`reconsideration_package` 必须同时保存对象引用 refs 与一份冻结后的卷宗内容快照 `snapshot / frozen_payload`，而不能只靠动态引用现场再拼。

---

## 73. `monitoring_run` 的最小 schema
### 73.1 `monitoring_run` 要回答的问题
它应回答：
- 这一轮差，本来为什么要跑
- 按什么版本跑
- 最后交了什么

### 73.2 建议结构
- `header`
- `links`：`case_id`、`task_id`、`task_version_id`、`pack_ids`、`latest_attempt_id`、`successful_attempt_id`、`report_id`
- `spec`：`run_kind`、`trigger_type`、`trigger_ref`、`expected_outputs_contract_ref`
- `state`：`status`、`attempt_count`、`last_attempt_status`、`completed_at`、`result_summary`
- `audit` / `ext`

### 73.3 时间语义必须分离
`monitoring_run` 必须同时显式记录：
- `planned_for_at`：制度上本来应何时执行
- `started_at / triggered_at`：实际上何时开始执行

---

## 74. `run_attempt` 的最小 schema
### 74.1 `run_attempt` 要回答的问题
它应回答：
- 为了完成这轮差，这一次尝试具体是怎么跑的
- 在什么环境下跑的
- 结果如何

### 74.2 建议结构
- `header`
- `links`：`case_id`、`task_id`、`run_id`、`previous_attempt_id`、`execution_session_id`、`scratch_ref`
- `spec`：`attempt_index`、`attempt_reason`、`execution_profile_snapshot`、`strategy_note`
- `state`：`status`、`started_at`、`ended_at`、`failure_class`、`failure_summary`、`promoted_artifact_refs`

### 74.3 冻结执行环境
每个 `run_attempt` 都必须在启动时保存一份不可变的 `execution_profile_snapshot`，明确冻结当时实际使用的模型、工具、权限与关键运行参数。

---

## 75. `fact_report` 作为一等对象
### 75.1 原则
`fact_report` 应当是一个独立的一等对象，专门包装并引用 `report.md + facts.json + artifacts.json` 三件套，而不是把三份文件直接视为“报告本体”。

### 75.2 建议结构
- `header`
- `links`：`case_id`、`task_id`、`run_id`、`successful_attempt_id`、`pack_ids`
- `spec`：`report_contract_ref`、`artifact_refs`、`observed_window`、`report_kind`
- `state`：`status`、`submitted_at`、`accepted_at`、`quality_summary`、`alert_summary`

---

## 76. `fact_report` 提交后冻结，不回改
### 76.1 不可变原则
`fact_report` 一旦进入 `submitted`，就应视为不可变。若需补件或修订，应创建新的 `fact_report` 对象，而不是回改旧报告。

### 76.2 报告谱系
建议通过以下字段串起谱系：
- `supersedes_report_id`
- `superseded_by_report_id`
- `report_lineage_id`

---

## 77. `internal_mail` 的最小 schema
### 77.1 `internal_mail` 要回答的问题
它应回答：
- 这封信是什么类型
- 它在提醒你什么
- 它指向哪些对象
- 你现在可以对它做什么

### 77.2 建议结构
- `header`
- `links`：`case_id`、`related_object_refs`、`source_op_id`、`source_session_id`
- `spec`：`message_type`、`title`、`summary`、`recommended_action`、`available_actions`
- `state`：`status`、`severity`、`acted_at`、`acted_action`、`consumed_by_op_id`
- `audit` / `ext`：`issuer_role` 等

### 77.3 消息快照原则
`internal_mail` 必须保存一份冻结的消息内容快照，而不能只是存几个 refs 然后每次打开时动态现拼。

---

## 78. `schedule_policy` 先作为版本内嵌值对象
### 78.1 原则
v1 的 `schedule_policy` 先作为 `task_version.spec` 中的内嵌值对象存在，而不是一上来单独做成一等对象。

### 78.2 可包含内容
例如：
- `mode`
- `timezone`
- `interval`
- `fixed_times`
- `windows`
- `misfire_policy`
- `catchup_policy`
- `supplemental_trigger_policy`

---

## 79. `tool_profile` 先作为版本内嵌冻结策略
### 79.1 原则
`tool_profile` 应像 `schedule_policy` 一样，先作为 `task_version.spec` 中的内嵌冻结策略存在；可以记录来源模板，但不能在运行时动态跟随外部模板漂移。

### 79.2 设计意义
这样可确保：
- 这版任务到底能做什么工具活是明确冻结的
- 旧版任务不会因外部模板变化而被污染

---

## 80. `credential_binding` 作为 `task` 级一等对象
### 80.1 原则
v1 应把 `credential_binding` 设计成 `task` 级独立对象，并用 `material_ref` 指向敏感材料本体；而不是把真实 API key / cookie / session 内容直接写进 `task` 或 `task_version` 的主 JSON。

### 80.2 建议结构
例如：
- `slot_name`
- `binding_type`
- `provider`
- `status`
- `validated_at`
- `expires_at`
- `material_ref`

---

## 81. 敏感材料本体与普通 workspace 分离
### 81.1 原则
真实的 API key / cookie / session 文件本体，应存放在独立于普通 `task workspace` 的受控安全区中；`task workspace` 里最多只出现运行时注入后的受控访问视图，而不直接把密钥文件当普通工作文件长期裸放。

### 81.2 设计意义
这样可避免敏感材料被：
- 错误打包进附件
- 错误发布进共享区
- 错误出现在日志或 artifacts 索引中

---

## 82. `run_attempt` 冻结非敏感凭证解析快照
### 82.1 原则
每个 `run_attempt` 都应保存一份不含敏感值的 `credential_resolution_snapshot`，明确记录本次实际解析并使用了哪些 `credential_binding_id`、它们当时的状态，以及是否走了备用绑定。

### 82.2 作用
它用于回答：
- 这次 attempt 当时到底用了哪套信物
- 为什么会报 `auth_expired`
- 第二次 attempt 成功是不是因为切了备用绑定

---

## 83. 当前已确认、但后续仍需继续展开的话题
以下议题已出现方向，但本稿暂不展开细则，待下一轮继续：
- Web 详细页面结构与状态流转细节
- 调度器与 runtime 的工程落地拆分
- 模板库、凭证接驳、任务 workspace 的具体存储方案
- 朝议结论文书与复议卷宗包的精确 schema
- 观察包、卷宗包、朝会轮次之间的数据落盘结构
- 对象类型注册表与通用读写器的实现方式
- `operation` / `timeline` / 索引的修复与重建机制
- `case / round / task / task_version / pack / review / briefing / run / attempt / report / mail` 的正式 JSON schema 示例

---

## 84. 结论
截至本稿，产品层、复议机制层与数据 schema 层的核心世界观已经明确：
- 顶层对象是 `case`，不是单个 `workflow_session`
- 候选任务、正式任务、任务版本、观察包、检察、复议都围绕 `case` 展开
- 监测任务是长期存在的治理对象，但执行以 `monitoring_run -> run_attempt` 分层进行
- 模板可复用，任务实例不共享执行体
- 运行默认无人值守，异常异步上呈
- 报告必须三件套交付，且 `fact_report` 作为正式对象存在
- 检察官只验卷，不越权定策，但可整理争议清单
- 复议默认读取正式卷宗，而不是全量旧 transcript
- 每轮朝会都沉淀正式结论文书三件套
- 卷宗包采用“最小基线 + 变化主轴 + 争议清单”的结构
- 卷宗包先预览，后决定是否开启复议，并支持 `deferred`、快照、版本链与后续再利用
- 数据层坚持 local-first、以 `cases/<case_id>/...` 为根、对象快照 + 轻量历史 + 可重建索引
- `operation`、`timeline`、`session`、`workspace`、`credential store` 各自分层，不互相冒充真相源
- 核心对象正在收束为统一外壳 schema，并逐步建立最小正式 schema 草案

这为后续正式 JSON schema 定稿、对象读写器实现、Web 交互落地、调度与 runtime 落地，建立了更完整且稳定的 PRD 基线。

