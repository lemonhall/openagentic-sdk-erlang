# 2026-03-06：朝议后专项监测、督办与复议系统 PRD（V1 草案）

## 文档状态
- 状态：讨论落盘版 PRD 草案
- 范围：固化当前已达成一致的产品设计决策
- 原则：PRD 不缩水，按完整产品愿景描述；后续实现再拆阶段
- 说明：本稿已经纳入前期基础设计，以及本轮新增的“复议卷宗包 / 结论文书 / 预览与 deferred”设计

---

## 1. 背景
当前三省六部 workflow 更偏向“一次朝会、一轮研判”。但很多真实议题并不是一次朝会就能完结，而是需要：
- 朝会中提出若干值得持续观察的指标、现象与假设
- 会后派出专门 agent 长期监测这些事项
- 周期性产出干巴巴、可追溯、可归档的事实材料
- 在一组监测结果成熟后，再触发下一轮复议

典型场景包括但不限于：
- 地缘政治冲突相关的能源、航运、制裁、军事活动指标
- 舆情热度与情绪结构变化
- 某类政策、市场、供应链指标的长期观测

因此，本系统不是一个普通的 cron 平台，而是一套：
- 由某次朝议触发
- 能长期办差
- 能周期性上呈材料
- 能形成督办与复议闭环
的长期治理系统。

---

## 2. 产品目标
本系统的核心目标是：

**把“一次性朝议”扩展为“朝议 -> 专项监测 -> 检察验卷 -> 再次复议”的长期治理闭环。**

它同时满足：
- 对用户而言，仍然像在治理一套“数字朝廷官僚体系”
- 对系统而言，拥有清晰的对象模型、工作区边界、权限边界和审计链
- 对监测 agent 而言，拥有长期 workspace、足够灵活的执行能力和自我改进空间
- 对后续复议而言，材料既适合人读，也适合系统自动装配上下文

---

## 3. 产品边界
### 3.1 本 PRD 覆盖的完整产品愿景
本 PRD 覆盖以下完整能力：
- 朝议后自动提取候选监测任务
- Web 右上角信箱式提醒
- 聊天式审议候选任务并生效 / 废弃
- 监测官按周期自动执行长期监测任务
- 周期性产出事实邸报
- 检察官检查一组报告是否齐备、是否言之有物
- 形成“可复议”通知或“重大异常急报”
- 用户点击后，开启新一轮朝会复议

### 3.2 明确不做的事情
本系统不应被设计成：
- ERP 风格的繁琐表单配置后台
- 只会跑固定命令的 cron 平台
- 运行到一半频繁停下来等待用户回答的半自动系统
- 把全部历史聊天全文无限叠加到同一个 session 的粗暴续写器

---

## 4. 基本设计原则
1. 顶层对象不是 `workflow_session`，而是长期存在的 **议题案卷 `case`**。
2. 模板可以复用，但任务实例绝不共享执行体。
3. 监测官可以自我改进“办差手段”，但不能擅自修改“差事本身”。
4. 普通任务定义走聊天式审议，敏感授权走单独接驳流程。
5. 运行时默认无人值守；出问题时异步上呈，不同步请示。
6. 任务之间默认隔离；共享只能通过 `case` 层正式发布材料发生。
7. 每一轮朝会、每一个监测任务、每一次运行，都必须可追溯、可复盘、可审计。

---

## 5. 核心对象模型
### 5.1 `case`
议题案卷，代表“伊朗局势”“某政策走势”“某市场监测”等长期议题本身。它是产品顶层容器，而不是某个单独的 workflow session。

### 5.2 `deliberation_round`
一次正式朝会轮次，包括首轮朝议、第一次复议、第二次复议等。每一轮都关联一个独立的 `workflow_session_id`。

### 5.3 `monitoring_candidate`
提案官从某轮朝会议事记录中提取出来的“候选监测任务”。候选任务先进入待审，不直接生效。

### 5.4 `monitoring_task`
经你审定并点击“生效”后的正式监测令。它只属于一个 `case`，不能跨案卷共享本体。

### 5.5 `task_version`
任务的版本定义。每次经过聊天式修订并正式生效后，产生一个新的任务版本；旧版本保留审计链。

### 5.6 `monitoring_run`
某个监测任务在某个时机被调度后的一次实际办差轮次。任务长期存在，但 run 是一次一次生成的独立执行。

### 5.7 `fact_report`
监测 run 产出的事实邸报，只讲事实、现象、变化、来源，不做战略判断。

### 5.8 `inspection_review`
检察官对一组报告做完整性与质量审查的结果。

### 5.9 `observation_pack`
观察包。它是某一次复议的触发单元，用于聚合一组应协同更新的监测任务。

### 5.10 `reconsideration_package`
复议卷宗包。它是某个时间点正式整理好的上呈材料快照，用于支撑是否开启新一轮复议。

### 5.11 `deliberation_resolution`
朝议结论文书。它是每个 `deliberation_round` 结束后的正式定稿对象，用于后续监测、复议和审计。

### 5.12 `task_template_library`
模板库。它存放监测思路、参考实现、数据源接入范式、脚手架与模板声明，但不共享正式任务实例。

### 5.13 `internal_mail`
内邮 / 奏折消息。用于在 Web 右上角信箱中统一呈现待审、异常、急报、可复议等通知。

---

## 6. 官员体系与职责分工
### 6.1 提案官
- 在某轮朝会结束后通读该轮 `workflow_session`
- 自动提取值得持续监测的事项
- 生成 `monitoring_candidate`
- 把候选任务投递到你的待审信箱

### 6.2 审议官
- 负责与你聊天式修订候选任务与正式任务
- 把自然语言讨论逐步沉淀成明确的任务定义
- 支持“废弃 / 生效”动作
- 支持已生效任务的后续版本化修订

### 6.3 监测官
- 负责周期性执行正式监测任务
- 拥有长期 `task workspace`
- 拥有联网、写脚本、执行脚本、保存状态等能力
- 可以自我改进执行实现层，但不能擅自改变任务宪章

### 6.4 检察官
- 只审材料是否齐备、是否可信、是否有信息密度
- 可整理争议点，但不做战略判断
- 不代替朝廷给出综合结论
- 负责“可复议 / 不足以复议 / 需补件 / 需督办”的审查判断

### 6.5 朝廷
- 仍由三省六部 workflow 承担综合研判职责
- 本系统只负责把后续事实材料准备好，再交还朝廷进行复议

---

## 7. Web 交互与治理体验
### 7.1 整体交互理念
界面不应设计成 ERP 式配置后台，而应尽量保持“与你的下臣议事”的治理体验。

### 7.2 右上角信箱提醒
Web 右上角提供统一“新奏折 / 内邮”提醒，用于提示：
- 候选监测任务待审
- 任务异常待整顿
- 观察包可复议
- 重大异常急报

### 7.3 聊天式审议页
点击候选任务或正式任务后，进入与该专属官员的聊天式治理界面，可在其中：
- 澄清监测目标
- 讨论频率、阈值、交付物
- 讨论数据源与方法
- 修订任务做事方式
- 最终执行“废弃 / 生效”动作

### 7.4 统一总览页
提供统一的管理视图，按树形结构展示：
- `case`
- 该案卷下的 `deliberation_round`
- 该案卷下的 `monitoring_task`
- 每个任务的运行记录与交付物

### 7.5 任务详情页
任务详情页至少包含：
- 任务定义
- 版本历史
- 运行记录
- 交付物列表
- 授权状态
- 治理会话入口

---

## 8. 生命周期与状态机
### 8.1 候选任务生命周期
`monitoring_candidate` 状态建议为：
- `extracted`
- `inbox_pending`
- `under_review`
- `discarded`
- `approved`

### 8.2 正式任务生命周期
`monitoring_task` 状态建议为：
- `active`
- `paused`
- `superseded`
- `closed`

### 8.3 任务版本
- 每次重大定义修订产生新的 `task_version`
- 只有被正式生效的版本才成为当前有效版本
- 旧版本必须保留，不直接覆写

### 8.4 监测 run 生命周期
`monitoring_run` 状态建议为：
- `scheduled`
- `running`
- `report_submitted`
- `failed`
- `needs_followup`

### 8.5 报告生命周期
`fact_report` 状态建议为：
- `draft`
- `submitted`
- `accepted`
- `rejected_for_revision`

### 8.6 检察生命周期
`inspection_review` 状态建议为：
- `pending`
- `reviewing`
- `ready_for_reconsideration`
- `insufficient`

### 8.7 一键复议的底层语义
点击“一键复议”时，不是续写旧 session，而是：
- 在同一个 `case` 下新建一个新的 `deliberation_round`
- 创建新的 `workflow_session_id`
- 自动挂载一份 `reconsideration_package`

用户体验上可以表现为“恢复旧朝会”；但技术实现上，每一轮应是新的 session，以保证审计清晰、链路清晰。

---

## 9. 观察包：复议的触发单元
### 9.1 基本定义
`observation_pack` 代表“为了回答某个明确复议问题而聚合的一组监测任务”。复议准备度以观察包为单位判断，而不是以单个任务判断。

### 9.2 观察包内容
观察包至少包含：
- `target_question`
- `task_ids`
- `freshness_window`
- `completeness_rule`
- `inspection_rule`
- `reconsideration_trigger_policy`

### 9.3 观察包状态
建议状态为：
- `collecting`
- `awaiting_inspection`
- `insufficient`
- `ready_for_reconsideration`
- `stale`
- `archived`

### 9.4 设计意义
这样系统判断“能否复议”时，看的是整包材料是否在当前周期内齐备、足够新鲜、足够可信，而不是某个单独任务有没有交卷。

---

## 10. 常报、急报与督办机制
### 10.1 常报
常规运行按任务定义的周期执行，产出 `fact_report`，再进入对应 `observation_pack`，等待整包达到复议条件。

### 10.2 急报
如果某个任务命中重大异常阈值，则允许不等整包齐活，直接生成一条 `urgent_brief` 投递到你的内邮。急报用于及时提醒，不自动替代整包复议。

### 10.3 督办
如果观察包长期缺件、任务反复失败、报告空洞，检察官可以形成督办意见，提示：
- 需要补件
- 需要整改
- 需要你介入治理该任务

---

## 11. 模板库、实例化与执行隔离
### 11.1 模板库的作用
模板库用于沉淀：
- 常见监测思路
- 参考脚本
- 数据源接入范式
- 解析与清洗脚手架
- 需要人工补齐的配置位

### 11.2 任务实例化原则
模板只负责“起草”和“参考实现”，不能形成共享执行体。正式任务一旦生效，必须实例化为：
- 自己独立的代码副本
- 自己独立的 workspace
- 自己独立的运行历史与状态文件

### 11.3 任务本体只属于一个 case
- 一个 `monitoring_task` 只能属于一个 `case`
- 同一个 `case` 下允许存在多个同主题监测变体
- 复用发生在模板层，不发生在实例执行体层

---

## 12. 授权与凭证接驳流程
### 12.1 任务讨论与敏感授权分轨
- 普通任务定义继续走聊天式审议
- 一旦涉及 API Key、Cookie、登录态、会话文件等敏感材料，应切换到单独的“授权接驳小流程”

### 12.2 模板与凭证的边界
模板库可以声明：
- 依赖哪些外部能力
- 需要哪些 secret slot
- 推荐接入哪些数据源
- 哪些授权步骤需要人工完成

但模板库不应携带共享密钥本体。

### 12.3 凭证归属
- API key 类能力可按模板声明的槽位进行绑定
- Cookie、登录态、会话文件等强运行态认证材料归属于具体 `task`
- 任务版本记录依赖哪些凭证槽位，但不持有凭证本体

### 12.4 任务状态补充
围绕授权可补充以下任务状态：
- `draft`
- `awaiting_credentials`
- `ready_to_activate`
- `active`
- `credential_expired`
- `reauthorization_required`

---

## 13. 任务宪章层与执行实现层分离
### 13.1 允许自我改进的范围
监测官可以在自己的 workspace 内持续改进：
- 抓取方式
- 本地脚本
- 解析逻辑
- 缓存与重试策略
- 备用数据源接入
- 运行稳定性

### 13.2 禁止擅自改变的范围
监测官不得自行改变以下任务宪章内容：
- 监测目标
- 报告周期
- 阈值
- 交付物结构
- 观察包归属
- 复议触发规则

这些变化必须通过新的 `task_version` 由你审议后生效。

---

## 14. 运行模型：长期任务，多次独立 run
### 14.1 总体模型
- `monitoring_task` 长期存在
- `monitoring_run` 按需一次次生成
- 任务长期拥有 workspace，但 agent 执行不是永远活着的常驻进程

### 14.2 每次 run 继承的上下文
每次 `monitoring_run` 应继承：
- 当前有效的 `task_version`
- 任务自己的 workspace
- 必要的凭证绑定
- 过往执行摘要
- 上次失败原因与最近产物摘要

### 14.3 设计意义
这种模型比“常驻 agent 永不退出”更适合：
- 调度
- 失败恢复
- 审计
- 资源隔离
- 长期演化

---

## 15. 会话模型与 Transcript 模型
### 15.1 治理会话
用于你与审议官持续讨论：
- 候选任务
- 正式任务定义
- 任务整改
- 新版本生效

### 15.2 执行会话
每次 `monitoring_run` 必须拥有一个可单独打开查看的独立 session / transcript，用于记录本次办差过程。

### 15.3 设计结果
一个任务至少分裂出两条清晰的历史线：
- “任务是怎么定义与修订的”
- “某一次差事是怎么实际执行的”

这样不会把治理对话与执行细节混在一起。

---

## 16. 无人值守运行与异常上呈
### 16.1 基本原则
监测任务默认必须支持**无人值守运行**。运行期间禁止同步向用户发起请示，不能把任务卡在等待你回复的状态。

### 16.2 异常处理流程
当遇到以下问题时：
- 验证码 / 二次登录
- Cookie 失效
- 数据源结构大改
- API 异常且无法自愈
- 事实冲突无法确认

监测官应：
1. 先按任务定义允许的策略自救
2. 自救失败后结束本次 run
3. 生成异常简报
4. 投递一条任务异常内邮

### 16.3 你的介入方式
你不参与正在执行中的 run，而是在事后：
- 打开任务治理界面
- 查看异常简报
- 与该任务官员对话
- 形成整改方案与新版本

---

## 17. 健康度、长期失败与待整顿机制
### 17.1 健康状态
每个任务除运行状态外，还应有长期健康状态，例如：
- `healthy`
- `degraded`
- `flaky`
- `rectification_required`
- `paused`

### 17.2 失败归因标准化
系统应对失败原因做标准化聚类，例如：
- `auth_expired`
- `source_unreachable`
- `source_schema_changed`
- `rate_limited`
- `script_runtime_error`
- `data_conflict_unresolved`
- `report_quality_insufficient`

### 17.3 自动待整顿
如果最近 `3-5` 个周期内连续出现同类失败，且任务未能自愈，则任务进入 `rectification_required`，停止继续机械执行，并向你投递“待整顿”通知。

---

## 18. 调度语义与时区规则
### 18.1 调度语义
v1 支持至少以下 4 类调度：
- 固定间隔（例如每 6 小时）
- 固定时点（例如每天 08:00）
- 时间窗口（例如工作日、交易时段）
- 事件触发补跑（例如急报后追加一次采集）

### 18.2 调度器职责
调度器负责决定何时生成 `monitoring_run`，真正的执行仍由监测官 agent 完成。

### 18.3 时区规则
每个监测任务必须显式带 `timezone`：
- 默认值为 `Asia/Shanghai`
- 允许按任务覆盖成其他市场时区
- 调度、freshness、观察包齐备判断都按任务自己的时区语义解释

---

## 19. 事实邸报三件套
### 19.1 强制交付物
每次 `monitoring_run` 至少产出以下三件套：
- `report.md`
- `facts.json`
- `artifacts.json`

### 19.2 三件套职责
- `report.md`：人读版事实邸报
- `facts.json`：结构化事实材料
- `artifacts.json`：附件索引

### 19.3 原则
监测官不能只交一篇散文化文字报告，必须同时交出可供系统消费的结构化材料。

---

## 20. 结构化事实模型（标准骨架 + 扩展字段）
### 20.1 统一骨架
`facts.json` 应采用“标准骨架 + 可扩展领域字段”的设计。统一骨架至少建议包含：
- `fact_id`
- `task_id`
- `run_id`
- `observed_at`
- `collected_at`
- `title`
- `fact_type`
- `source`
- `source_url`
- `collection_method`
- `value_summary`
- `change_summary`
- `alert_level`
- `confidence_note`
- `evidence_refs`

### 20.2 可扩展领域字段
不同任务领域可附带扩展字段，例如：
- 能源类字段
- 航运类字段
- 舆情类字段
- 军事情报类字段

### 20.3 原则
系统层优先依赖统一骨架完成治理与复议支持；更深细节通过扩展字段和附件补充。

---

## 21. 检察官职责边界
### 21.1 检察官负责什么
检察官负责审查：
- 是否按时交卷
- 是否覆盖关键指标
- 是否有明确来源与证据
- 是否存在明显空话、套话
- 是否足以支撑进入复议

### 21.2 检察官不负责什么
检察官不应：
- 替朝廷做综合战略判断
- 给出最终政策结论
- 越权决定如何应对外部形势

### 21.3 分工原则
- 监测官负责办差
- 检察官负责验卷
- 朝廷负责定策
- 你负责拍板

---

## 22. 内邮系统 / 奏折信箱模型
### 22.1 信箱能力
内邮系统至少支持：
- `未读 / 已读 / 归档`
- 按消息类型筛选
- 关联对象跳转
- 一眼可见严重级别与建议动作

### 22.2 典型消息类型
至少包括：
- 候选监测任务待审
- 任务异常待整顿
- 观察包可复议
- 重大异常急报

### 22.3 消息字段
建议包含：
- `message_type`
- `case_id`
- `related_object_type`
- `related_object_id`
- `issuer_role`
- `severity`
- `title`
- `summary`
- `recommended_action`
- `created_at`
- `evidence_refs`

### 22.4 一键动作
简单动作可直接在邮件上执行，例如：
- 生效任务
- 废弃候选
- 暂停任务
- 开启复议

复杂整改应进入治理界面完成。

---

## 23. 权限模型与能力边界
### 23.1 监测官默认能力
监测官应默认具备：
- 访问互联网
- 在自己的 task workspace 内读写文件
- 创建和执行脚本
- 保存缓存、日志、抓取结果

### 23.2 监测官默认限制
监测官默认不得：
- 修改仓库源码
- 修改其他任务的 workspace
- 读写其他 case 的私有材料
- 访问不属于自己的敏感凭证

### 23.3 凭证边界
监测官只能读取当前任务绑定的 secret / cookie / session binding，不得跨任务访问其他授权材料。

### 23.4 高风险副作用
未来若支持发帖、下单、远程控制等高风险动作，应另设更高权限模型，不混入普通监测任务。

---

## 24. 工作区隔离与案卷共享材料
### 24.1 任务私有 workspace
每个 `monitoring_task` 都有自己的独立 `task workspace`，用于存放：
- 调试脚本
- 中间产物
- 抓取结果
- 缓存
- 登录态
- 失败痕迹

### 24.2 案卷共享材料区
`case` 层应有一个“正式发布材料区”，用于存放：
- 上一轮朝会议结论摘要
- 已验收的事实邸报
- 检察官形成的观察包摘要
- 允许同案任务引用的附件与正式材料

### 24.3 共享原则
默认情况下，监测任务之间不能直接互读彼此的私有 workspace；如果需要共享，只能通过 `case` 层正式发布的材料区发生。

---

## 25. 复议卷宗包：默认读卷宗，不默认读全文
### 25.1 设计原则
新一轮复议时，朝廷默认应读取整理好的正式卷宗材料，而不是默认全量重读历次朝会 transcript。历史全文只作为可追索材料，按需下钻。

### 25.2 `reconsideration_package` 的地位
`reconsideration_package` 必须是一个正式对象，而不是 runtime 临时拼出来的一段 prompt。它应当可归档、可审计、可复用，并作为多轮复议链条中的正式材料节点存在。

### 25.3 卷宗包的基本结构
卷宗包至少应包含以下层次：
- 案由层：`case` 是什么，为什么持续观察
- 上轮结论层：上一轮朝会到底形成了什么正式判断
- 新增事实层：自上一轮以来新增且已验收的事实邸报摘要
- 监测态势层：当前仍生效、暂停、整顿中的任务概况
- 检察摘要层：材料是否齐备、可信、值得复议

---

## 26. 每轮朝会都必须沉淀正式结论文书
### 26.1 基本原则
每个 `deliberation_round` 结束后，不能只留下 transcript，还必须沉淀一份正式结论文书，作为后续监测、复议与审计的稳定锚点。

### 26.2 正式对象
建议引入正式对象：
- `deliberation_resolution`
- 中文可称为“朝议结论文书”

### 26.3 文书承担的职责
它至少应服务于：
- 给你阅读本轮朝会到底形成了什么结论
- 给下一轮复议提供“上一轮正式立场”
- 给监测体系提供后续应继续观察的事项
- 给审计与复盘提供稳定定稿，而不是重新从 transcript 猜结论

---

## 27. 朝议结论文书三件套
### 27.1 强制交付物
每个 `deliberation_round` 结束后，至少产出：
- `resolution.md`
- `resolution.json`
- `resolution_refs.json`

### 27.2 三件套职责分工
- `resolution.md`：给你和后续朝廷直接阅读的人读版
- `resolution.json`：给系统做多轮复议上下文组装、轮次比对、治理逻辑使用
- `resolution_refs.json`：关联本轮结论所引用的事实邸报、观察包、急报与关键 transcript 片段索引

### 27.3 系统默认读取方式
在一键复议时，系统默认以 `resolution.json` 为主进行组装，不直接把上一轮 `resolution.md` 原文整段塞入 prompt；`Markdown` 版本用于人读与展示。

---

## 28. 复议卷宗包的装配顺序：以变化为主轴
### 28.1 默认装配顺序
复议卷宗包建议固定按以下顺序装配：
1. 案卷抬头：案由、当前轮次、复议触发原因
2. 上一轮正式结论：来自上一轮 `resolution.json`
3. 本次新增事实摘要：来自观察包中已验收的报告材料
4. 检察官意见：材料齐备性与可信度摘要
5. 当前监测态势：哪些任务 active / paused / rectification_required
6. 可追索材料索引：原始 transcript、附件、截图、CSV、日志等

### 28.2 阅读哲学
复议卷宗包必须突出“变化量（delta）”，而不是平铺所有历史事实。核心体验应当是：
- 上一轮我们怎么想
- 这段时间新增了什么
- 因此这次为何值得重新判断

---

## 29. 最小基线 + 变化主轴
### 29.1 设计原则
卷宗包不应是“纯 delta 包”，而应采用“最小基线 + 变化主轴”的结构：
- 基线事实层：保留极少量仍然支撑理解全局的稳定锚点
- 变化事实层：展示自上一轮以来新增、修正、强化、削弱、推翻的事实

### 29.2 设计意义
这样既避免把所有旧材料重新灌入复议上下文，也避免朝廷只看到增量新闻而失去长期案卷连续感。

---

## 30. 最小基线事实必须由上一轮显式指定
### 30.1 基本原则
最小基线事实不应由复议时临场抽取，而应由上一轮朝议在生成 `resolution.json` 时显式指定给下一轮。

### 30.2 建议字段
建议在 `resolution.json` 中加入：
- `baseline_facts_for_next_round`
- `deprecated_baseline_facts`
- `rationale_for_baseline_changes`

### 30.3 设计意义
这样系统不需要临场猜测“哪些旧事实还重要”，而是直接沿用上一轮定稿中明确保留下来的基线锚点。

---

## 31. 变化事实必须做显式分类
### 31.1 `delta_type`
进入复议卷宗包的变化事实，必须具备显式分类，至少包括：
- `new_fact`
- `updated_fact`
- `strengthened_fact`
- `weakened_fact`
- `invalidated_fact`

### 31.2 辅助字段
建议同时附带：
- `delta_against_round`
- `impact_hint`

### 31.3 原则
变化事实不能只是按时间顺序堆新增材料，而应明确表达“这是新增、修正、强化、削弱，还是推翻旧前提”。

---

## 32. 变化分类的职责分工
### 32.1 监测官的职责
监测官在产出 `facts.json` 时，对事实变化做初步判类，因为它最了解本次 run 相比上次 run 到底发生了什么。

### 32.2 检察官的职责
检察官不负责重做领域判断，但要检查：
- 判类是否明显离谱
- 是否有证据支撑
- 是否存在低质量变化分类

### 32.3 朝廷的职责
朝廷在正式复议中负责判断这些变化对整体认知意味着什么，并在新的 `resolution.json` 中沉淀战略层面的变化结论。

### 32.4 分层原则
变化语义必须分层：
- 事实层变化：由监测官初判
- 变化质量检查：由检察官把关
- 战略层变化：由朝廷在正式结论文书中定稿

---

## 33. 争议清单：说明“为什么值得再议”
### 33.1 设计目的
复议卷宗包里应当显式包含一份 `controversies`（争议清单），用于说明这次为什么值得重新议。

### 33.2 争议清单至少包含
- 事实冲突：不同来源、不同任务、不同周期结果互相矛盾
- 解释分歧：同一组变化可能导向两种不同理解
- 关键不确定性：材料虽齐，但仍有关键未知项尚未被证实

### 33.3 作用边界
争议清单不是替朝廷下判断，而是把争点与不确定点显式列出，帮助本轮复议聚焦真正需要再议的问题。

---

## 34. 争议清单由检察官主整理
### 34.1 职责分配
- 监测官：仅报告本任务范围内观察到的冲突、异常与解释困难
- 检察官：横向汇总多个任务之间的冲突，形成案卷级争议清单草案
- 朝廷：在正式复议中处理争议，并形成新的正式结论

### 34.2 原则
案卷级 `controversies` 的主整理人应当是检察官，而不是单个监测官，也不是朝廷 runtime 在现场临时抽取。

---

## 35. 复议卷宗预览页与用户动作
### 35.1 先阅卷，再开朝会
点击“可复议”内邮后，不应直接开朝会，而应先进入“复议卷宗预览页”，让你先看本次整理好的上呈材料，再决定是否正式开启复议。

### 35.2 预览页至少展示
- 案卷名
- 本次复议触发原因
- 新增事实摘要
- 争议清单摘要
- 检察官结论
- 将纳入本轮复议的报告列表

### 35.3 预览页主要动作
预览页至少提供两个主动作：
- `开启复议`
- `继续观察`

### 35.4 `继续观察` 的语义
`继续观察` 不是否决材料，而是表示：
- 当前卷宗已经阅过
- 暂不触发新的 `deliberation_round`
- 观察包继续收集后续材料

---

## 36. 卷宗包生命周期：deferred、快照与版本链
### 36.1 `deferred`
当你点击 `继续观察` 时，当前卷宗包应保留并进入 `deferred` 状态，而不是被丢弃。

### 36.2 卷宗包必须是不可变快照
卷宗包一旦生成，就应是不可变快照。后续新增材料不应改写旧卷宗，而应生成新的卷宗包，并可将旧卷宗标记为 `superseded`。

### 36.3 同一观察包下可有多版卷宗
同一个 `observation_pack` 可以关联多版复议卷宗包；卷宗包自身应具备明确版本号与先后链条。

### 36.4 人类可读编号
卷宗包除内部 ID 外，还应有面向 UI、内邮、审计与人工讨论的展示编号体系，用于清晰表达：
- 属于哪个 `case`
- 属于哪个 `observation_pack`
- 是该包下第几版卷宗

### 36.5 不预绑定未来轮次
卷宗包在生成时不预绑定未来 `deliberation_round`。只有当你点击 `开启复议` 时，系统才：
- 创建新的 `deliberation_round`
- 分配新的 `workflow_session_id`
- 将当前卷宗包标记为 `consumed_by_round`

### 36.6 `deferred` 卷宗包的再利用
已 `deferred` 的卷宗包不是永久失效。只要仍满足新鲜度要求且未被更新版替代，就允许在后续被重新拿来开启复议；若已失鲜或已被新版 supersede，则应提示你优先查看新版卷宗。

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
