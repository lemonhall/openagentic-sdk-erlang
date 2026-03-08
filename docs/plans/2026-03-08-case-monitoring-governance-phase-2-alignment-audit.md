# 2026-03-08：Phase 2｜监测执行与事实上呈实现对齐审计（第二轮）

## 文档状态
- 状态：第二轮对齐前置文档 / 实现审计快照
- 处理状态：【已完成】
- 审计时间：2026-03-08
- 审计对象：仓库当前已落地的 Phase 2 相关实现
- 审计目标：回答 **Phase 2 设计稿里哪些已经落地，哪些只落了一半，哪些仍是下一步必须补齐的缺口**

---

## 1. 为什么要有这份文档
- `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-2-monitoring-execution-and-fact-delivery.md` 已经给出了 Phase 2 的目标、边界、DoD 与数据骨架。
- 但当前仓库并不是“Phase 2 还没开始”，而是已经具备了第一版可运行骨架：`monitoring_task -> monitoring_run -> run_attempt -> fact_report` 已经能落盘、能跑、能测。
- 如果不先做一次实现审计，直接继续施工，很容易出现三类偏差：
  - 把已经存在的能力重复实现一遍；
  - 把真正的缺口和 Phase 3/4 的后续能力混在一起；
  - 让设计稿、代码、测试再次漂移。

因此，这份文档不是替代 Phase 2 设计稿，而是作为“**当前现实与 Phase 2 目标之间的对齐说明书**”，供下一轮对齐施工直接引用。

---

## 2. 规范来源与现实证据

### 2.1 本轮对齐以哪些设计文档为准
本轮“应该做到什么”的判断，主要以以下文档为准：

1. Phase 2 直接施工基准：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-phase-2-monitoring-execution-and-fact-delivery.md`

2. 全局产品与制度机制：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-prd-main.md`
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-domain-mechanism-design.md`

3. 全量数据与 Schema：
   - `docs/plans/2026-03-06-case-monitoring-governance-and-reconsideration-data-and-schema-design.md`

### 2.2 本轮现实审计主要看的实现文件
- 核心存储与执行主链：
  - `apps/openagentic_sdk/src/openagentic_case_store.erl`

- Web API：
  - `apps/openagentic_sdk/src/openagentic_web.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_sessions_query.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_tasks_detail.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_tasks_run.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_runs_retry.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_task_credential_bindings.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_tasks_activate.erl`
  - `apps/openagentic_sdk/src/openagentic_web_api_tasks_revise.erl`

- Web 页面与前端：
  - `apps/openagentic_sdk/priv/web/view/governance-session.html`
  - `apps/openagentic_sdk/priv/web/assets/governance-session.js`
  - `apps/openagentic_sdk/priv/web/view/task-detail.html`
  - `apps/openagentic_sdk/priv/web/assets/task-detail.js`

- 测试证据：
  - `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
  - `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`

### 2.3 本轮验证证据
本轮不是只靠“读代码猜测”，而是做了新鲜验证：

- 运行命令：
  - `rebar3 eunit --module=openagentic_case_store_test --module=openagentic_web_case_governance_test`

- 结果：
  - `16 tests, 0 failures`

这意味着下文对“当前现实”的描述，至少已经被关键 Phase 2 路径上的现有测试覆盖过一轮。

---

## 3. 一句话总判断

**当前仓库已经具备了 Phase 2 的第一版“手工执行主链 + 数据骨架”，但还没有完成文档要求的“可调度、真无人值守、自愈失败后异常上呈、contract 真正判卷、attempt/report 可治理回看”的第二轮对齐。**

换句话说：

- **已经不是 0 到 1 阶段**；
- 但 **离 Phase 2 文档里的 DoD 还差关键收口项**；
- 下一轮施工应以“补齐对齐缺口”为主，而不是重做基础骨架。

---

## 4. 已经对齐的部分

### 4.1 `monitoring_run / run_attempt / fact_report` 分层已经存在
当前实现已经有清晰的业务分层：

- `monitoring_run` 代表一轮业务监测；
- `run_attempt` 代表为完成这轮业务而发起的一次具体尝试；
- `fact_report` 代表成功尝试后的正式事实上呈对象。

这部分与 Phase 2 文档关于 §57、§73、§74、§75 的主张基本一致。

在实现上可以直接看到：

- `run_task/2` 创建 `monitoring_run`
- `execute_run_attempt/7` 创建 `run_attempt`
- `finalize_run_success/8` 创建 `fact_report`

这说明 Phase 2 最核心的对象骨架已经不是设计稿，而是实际代码能力。

### 4.2 独立执行 transcript 已落地
每个 `run_attempt` 都会创建独立 `execution_session_id`，并将运行事件写入 session transcript。也就是说，治理会话与执行会话已经在对象层面分离，而不是混在一条 session 里。

这与 Phase 2 文档 §15、§54、§57 的方向一致。

### 4.3 长期 `task workspace` 与 `attempt scratch` 已经分层
当前实现已经区分：

- 长期 `task workspace`
- 尝试级 `attempt scratch`

而且 run 时默认工作目录落在 scratch，成功后再把 `report.md`、`facts.json`、`artifacts.json` 与附件索引提升为正式交付物。这与 §58、§59 的主张是对齐的。

### 4.4 `fact_report` 已是一等对象，而不是三件套散落文件
成功执行后，并不是只留下三件套文件，而是会额外生成 `fact_report` JSON 对象，把：

- `report_contract_ref`
- `artifact_refs`
- `observed_window`
- `report_kind`
- `submitted_at`

等信息包装进正式对象中。这一点与 §75 的方向一致。

### 4.5 凭证绑定与非敏感解析快照已有第一版
当前仓库已经具备：

- `credential_binding` 作为 `task` 级独立对象；
- `material_ref` 指向敏感材料位置；
- `run_attempt.spec.credential_resolution_snapshot` 记录本次尝试使用了哪些绑定。

这说明 §80、§82 并非完全未做，而是已经有第一版可用骨架。

### 4.6 失败归因与“待整顿”第一版已存在
当前实现对失败原因已经做了标准化字段承载，并且在连续同类失败累计到阈值后，可以把任务打到 `rectification_required`，同时发一封 `internal_mail`。

这说明 §16、§17 中“异常不静默吞掉”“长期失败要进入治理流程”的方向，已经有了第一版落地。

---

## 5. 只对齐了一半的部分

### 5.1 文档要求“无人值守运行”，现实是“不会卡住用户，但也没有完整自愈闭环”
当前 run 路径并没有配置 `user_answerer`，因此运行过程中不会真的同步等用户回复；在这个意义上，它是“不会把任务卡在等待人工确认”的。

但问题在于：

- 当前实现更多是 **fail-closed**；
- 还不是文档所说的“按任务定义允许的策略先自救，再在自救失败后形成异常简报和异常上呈”。

也就是说，**“不阻塞用户”这一点勉强成立，但“无人值守运行机制完整闭环”还没有成立。**

### 5.2 执行环境冻结已有，但冻结内容还不够完整
`execution_profile_snapshot` 已经会记录：

- provider/model/base_url
- allowed_tools
- tool_profile
- schedule_policy
- permission_mode
- max_steps
- scratch_ref

这已经相当接近 §74.3 的要求。

但当前仍缺几层“真实执行上下文冻结”：

- 与长期 `task workspace` 的实际挂接信息
- 最近治理结论 / 最近异常摘要
- 过往执行摘要或上一轮运行的关键结果

所以它更像“运行参数快照”，还不是完整的“监测官实际办差环境快照”。

### 5.3 `task workspace` 已创建，但还没有真正变成监测官的长期工作面
现在任务一经生效就会创建长期 workspace，并写入初始 `TASK.md`。这说明“任务级长期空间”不是空概念。

但真正跑 run 时，runtime 的 `workspace_dir` 用的是 scratch，而不是 task workspace。治理会话继续对话时，也没有自动把 task workspace 或任务上下文装配进 runtime 请求。

结果是：

- 长期 workspace 虽然存在；
- 但运行期与治理期都没有自然“住进去”。

这会导致文档里强调的“脚本、配置、缓存、稳定方法实现长期积累在 task workspace”只落了一半。

### 5.4 事实三件套已经强制存在，但 `report_contract` 还没有真正变成判卷规则
当前实现已经强制要求交：

- `report.md`
- `facts.json`
- `artifacts.json`
- 至少一个可追溯来源引用

这与 §19、§20、§68 的“系统底线”基本一致。

但当前 `report_contract` 的地位主要还是：

- 被存进 `task_version.spec`
- 被放进 prompt 提示模型

真正校验时，系统只按统一最低线检查，并没有按每个版本自定义的 contract 扩展去判卷。因此，**“字段已经存在”，但“contract 已执行化”还没有成立。**

### 5.5 执行 transcript 已落盘，但治理端还不能完整回看 attempts / reports
当前 detail API 会返回：

- `task`
- `versions`
- `credential_bindings`
- `authorization`
- `runs`
- 聚合后的 `artifacts`

但不会直接返回：

- `run_attempts`
- `fact_reports`

前端任务详情页也只展示 runs 和 artifacts，没有把 attempts、report 列表、report 谱系、attempt session 入口作为正式治理视图的一部分。

因此，这部分是“底层对象有了，治理界面还没补齐”。

### 5.6 `fact_report` 的不可变原则基本成立，但生命周期还没展开
从当前实现看：

- `fact_report` 一旦创建就是 `submitted`
- 没有回改 API
- 也没有覆盖式更新旧报告的入口

这在行为上已经接近 §76 的“提交后冻结”。

但它还没有展开成完整生命周期：

- `draft`
- `submitted`
- `accepted`
- `rejected_for_revision`

所以可以说：**不可变原则基本成立，状态机尚未对齐。**

---

## 6. 仍未对齐、且下一轮必须补齐的核心缺口

### 6.1 调度器尚未落地，`schedule_policy` 目前只是冻结值，不是执行机制
这是当前最大的缺口之一。

Phase 2 文档明确要求：

- 支持固定间隔、固定时点、时间窗口、事件触发补跑等调度语义；
- 调度器负责决定何时生成 `monitoring_run`；
- 按任务自己的时区解释调度与 freshness。

而当前现实是：

- `schedule_policy` 会存入 `task_version.spec`
- `monitoring_run` 会记录 `planned_for_at`
- 但 run 入口仍是手工 `POST /tasks/:task_id/run`

也就是说，**调度相关的数据骨架已有，调度执行器仍不存在。**

### 6.2 治理会话的“上下文装配”还没做
Phase 2 文档 §55.2 明确要求，继续治理对话时默认应装配：

- 当前 `task.json`
- 当前生效 `task_version`
- 历史版本摘要
- 最近治理对话
- 上次整改结论或异常摘要

当前 `POST /api/sessions/:sid/query` 只是对既有 session 做普通 `resume_session_id` 查询，并没有自动把这些治理上下文注入进去。

因此，**会话 ID 复用了，但“同一任务长期单线治理”的上下文组装机制还未实现。**

### 6.3 run 继承长期任务上下文的逻辑还不够
Phase 2 文档 §14 和 §15 的核心不是“每次 run 都开个新 session”这么简单，而是：

- 每次 run 要继承任务宪章、当前版本、长期方法资产、过往执行摘要；
- 让 run 是“同一个长期差事的又一次执行”，而不是一次完全孤立的临时问答。

当前 `build_monitoring_prompt/3` 只注入了：

- task 基础字段
- 当前 version
- schedule_policy
- report_contract
- 当前 attempt 的 scratch 与 credential snapshot

但没有注入：

- task workspace 位置
- 上轮交付摘要
- 最近失败原因
- 历史执行摘要
- 最近整改结论

这会让 run 虽然能跑，但长期治理感与方法积累感不足。

### 6.4 异常上呈链条还不完整
文档 §16 的要求是：

1. 先自救
2. 自救失败后结束本次 run
3. 生成异常简报
4. 投递任务异常内邮

当前实现只有：

- 失败写 scratch 输出
- 更新 attempt/run/task 状态
- 连续失败达到阈值后投递“待整顿”内邮

缺的是：

- 每次失败后的标准异常简报对象
- 每次失败都可见的异常内邮
- 可区分“本次失败但未到待整顿阈值”与“已进入待整顿”的治理动作

### 6.5 失败分类仍偏粗，不足以支撑长期治理
当前实现能稳定产出的失败类，主要还是：

- `report_quality_insufficient`
- `script_runtime_error`

而文档要求的长期治理分类还包括：

- `auth_expired`
- `source_unreachable`
- `source_schema_changed`
- `rate_limited`
- `data_conflict_unresolved`

如果不补齐这套分类，后续的：

- 失败聚类
- 整改建议模板
- 自动待整顿
- 复盘报表

都会显得过于粗糙。

### 6.6 run / report 状态机尚未对齐设计稿
当前代码里：

- `monitoring_run` 主要用 `pending / running / completed / failed`
- `fact_report` 主要是 `submitted`

而文档稿希望看到更细粒度状态，例如：

- run：`scheduled / running / report_submitted / failed / needs_followup`
- report：`draft / submitted / accepted / rejected_for_revision`

如果下一轮目标是“严格对齐 Phase 2 文档”，这部分需要补齐；如果目标是“先把机制闭环跑通”，则可以在优先级上放到调度器、异常上呈、contract 判卷之后。

### 6.7 `report_contract` 必须从“字段”升级成“机器可执行规则”
这是第二轮必须补的另一个关键缺口。

当前已经证明：

- 存 contract 没问题；
- 给模型看 contract 没问题。

但如果系统自身不按 contract 判卷，那么：

- 版本差异对交付要求的影响不可验证；
- 新版本 contract 的治理价值会大打折扣；
- “为什么这次交卷不合格”无法回到正式版本语义上解释。

因此，下轮必须把 `report_contract` 从静态字段升级为实际验收逻辑。

### 6.8 任务详情 / 治理页面还缺正式“run history 视图”
当前任务详情页已经有雏形，但还不够支撑文档里强调的“可追溯、可复盘、可治理”。

至少还缺：

- 按 run 查看 attempt 列表
- 查看每个 attempt 的 `execution_session_id`
- 查看每个 report 的状态、谱系与三件套引用
- 区分“失败 attempt scratch”和“正式 promote 交付物”

这部分不一定要做成重页面，但 API 与页面至少要能把底层对象真正呈现出来。

---

## 7. 当前不应误判为缺口的部分

以下内容虽然在代码里还没有完整展开，但 **本轮不应误判为 Phase 2 未完成的核心阻塞项**：

### 7.1 `pack_ids` 目前为空是可以接受的
当前 `monitoring_run.links.pack_ids`、`fact_report.links.pack_ids` 都是空数组占位。这说明 Observation Pack 关联尚未打通。

但根据 Phase 2 文档的实现边界：

- 观察包验卷
- 卷宗预览页
- `deferred` 生命周期
- 更完整的派生索引与时间线

本就不要求在这一阶段完全落地，因此它们当前为空，不应被视为本轮首要缺陷。

### 7.2 检察官验卷与 `accepted/rejected` 还没完全做，不等于 run 主链无效
检察生命周期与 Observation Pack 体系更接近 Phase 3 主战场。当前 Phase 2 重点仍应是：

- 能调度
- 能执行
- 能产出三件套
- 能失败治理

因此，report 生命周期未完整展开，是缺口，但不是要先于调度器和 contract 验卷去补的缺口。

---

## 8. 第二轮对齐建议：按优先级拆成三个批次

### 8.1 P0：必须先补的闭环项
这些不补，Phase 2 不能算真正收口：

1. **调度器落地**
   - 让 `schedule_policy` 不再只是存档值，而是真能生成 `monitoring_run`

2. **run 上下文装配增强**
   - 注入 task workspace、历史执行摘要、最近异常/整改摘要

3. **异常上呈闭环**
   - 每次失败生成异常简报对象或异常 mail
   - 区分“单次失败”和“进入待整顿”

4. **`report_contract` 执行化**
   - 系统按 version 自己的 contract 判卷，而不仅是最低线校验

### 8.2 P1：补齐治理可见性
这些直接影响“可复盘、可审计、可治理”的体验：

1. `task detail` API 暴露 `run_attempts`
2. `task detail` API 暴露 `fact_reports`
3. 前端展示 attempt 列表、report 列表、execution session 入口
4. 区分 scratch 残留与 promoted 正式交付

### 8.3 P2：状态机与分类细化
这些对长期成熟度很重要，但可排在主闭环之后：

1. 细化 run 状态机
2. 展开 report 生命周期
3. 丰富 failure_class 标准化分类
4. 在治理页面展示更明确的健康度演进

---

## 9. 建议的下一轮施工顺序

为了减少返工，建议下一轮按以下顺序对齐：

### 9.1 先补“调度与执行主链”，再补治理页
原因：

- 如果没有调度器，很多运行状态与 `planned_for_at` 语义都只是手工模拟；
- 先把真实 run 生成机制补上，再做页面，会减少 UI 返工。

### 9.2 先补 `report_contract` 执行化，再补 report 生命周期细化
原因：

- 如果 contract 还不能机器判卷，先做 `accepted / rejected_for_revision` 只会变成外壳状态；
- 应先让系统知道“为什么这卷不合格”，再去扩展报告状态机。

### 9.3 先补 attempt/report API，再补 richer UI 呈现
原因：

- 底层对象现在已经存在；
- 优先把 API 补全，页面就能更自然地消费；
- 也更利于测试先行。

---

## 10. 本轮审计后的明确结论

截至 2026-03-08，可以明确下结论：

1. **Phase 2 并不是“还没开始”**
   - 第一版执行骨架已经落地，并且已有关键 EUnit 证明主链可跑。

2. **但 Phase 2 也不能视为“已经完成”**
   - 目前完成的是“手工 run + attempt + report + failure baseline”。
   - 尚未完成的是“调度执行化、异常上呈闭环、contract 判卷、run/report 治理可见性”。

3. **下一轮应该以“补齐第二轮对齐缺口”为主，不应该重写骨架**
   - 应复用现有 `openagentic_case_store` 主链、现有 Web API 入口、现有 EUnit 骨架；
   - 在其上增量补齐对齐项，而不是推翻重做。

---

## 11. 可直接转化为施工计划的对齐清单

下一轮施工计划，建议直接围绕下面这些条目展开：

- [x] 让 `schedule_policy` 真正驱动 `monitoring_run` 生成
- [x] 为 run 注入 task workspace、历史执行摘要、最近异常/整改摘要
- [x] 为单次失败生成标准异常简报与异常 mail
- [x] 扩充 `failure_class` 分类并在长期失败统计中使用
- [x] 将 `report_contract` 升级为真正的交卷验收逻辑
- [x] 在 task detail API 中返回 `run_attempts`
- [x] 在 task detail API 中返回 `fact_reports`
- [x] 在前端展示 attempt / report / transcript / report lineage
- [x] 细化 `monitoring_run` 与 `fact_report` 的生命周期状态

这 9 条如果完成，Phase 2 才能从“第一版可运行原型”进入“与设计稿基本对齐”的状态。



## 12. 收尾结论（2026-03-08）
- 处理状态：【已完成】
- 本轮已补齐：
  - `schedule_policy` 已由 `openagentic_case_scheduler` 落成实际调度
  - 任务执行上下文已注入 task workspace、历史版本/执行/异常摘要
  - 失败路径会产出 `exception_brief`、失败 mail 与 failure stats
  - `report_contract` 已执行化校验，不再只是静态字段
  - `task detail` API / 页面已补齐 `run_attempts`、`fact_reports`、`execution_session_id` 与 report lineage
  - 治理续聊已支持 `case_id` / `task_id`，并注入 `TASK_GOVERNANCE_CONTEXT_V1`
- 验证：
  - `rebar3 eunit --module=openagentic_case_store_test --module=openagentic_web_case_governance_test` -> 19 tests, 0 failures
  - `rebar3 eunit` -> 本轮观察到 161 tests, 0 failures, 3 cancelled（取消项表现为既有套件超时/挂起，不是本次新增失败）
