# Phase 3 Alignment Audit — Round 4

## 1. Audit goal

本轮审计只处理 Round 3 留下的 5 个细粒度残差，目标不是再扩 Phase 3 范围，而是确认这些残差是否已经被代码、测试与文档共同收口。

Round 3 的 5 类残差在 round-4 执行中被拆成 6 个闭环点：
- `reconsideration_package` 缺少显式 pack-local 版本字段
- `reconsideration_package` 显示编号缺少 pack/version 语义
- `inspect_observation_pack` 未纳入 revision gate
- `operation` 只有 happy-path，没有 `partially_applied / failed`
- `urgent_brief` 未进入 `timeline.jsonl`
- `inspection_review.reviewing` 仍未形成正式顶层状态轨迹

## 2. Round 4 closure result

### 2.1 卷宗版本语义已闭合
当前 `reconsideration_package` 已补出两层版本表达：
- `links.pack_version`
- `state.version_no`

同一 `observation_pack` 下再次出卷时，版本号会递增；首版为 `1`，后续版按 pack-local 序号单调增加。

### 2.2 卷宗显示编号已具备 pack/version 语义
当前 `reconsideration_package.state.display_code` 已从泛化 `BRIEF-*` 升级为带 pack/version 语义的编号，例如：
- `PACK-<pack_id>-V1`
- `PACK-<pack_id>-V2`

这意味着不需要再只靠 supersede 链条反推“这是第几版卷宗”。

### 2.3 `inspect_observation_pack` 已纳入 revision gate
当前 store 与 Web handler 都已支持：
- inspect 写路径读取可选 `current_revision`
- revision 不匹配时返回 `revision_conflict`
- Web API 以 `409` 返回 `current_revision`

至此，Phase 3 的关键写路径已经统一进入同一类 optimistic concurrency 语义。

### 2.4 `urgent_brief` 已进入 case timeline
监测运行命中重大异常阈值时，系统现在不只会：
- 生成 `urgent_brief` 对象
- 投递 `urgent_brief` 内邮

还会 best-effort 追加一条：
- `timeline.event_type = urgent_brief_triggered`

因此案卷编年史已能看到“某次急报触发”的正式痕迹。

### 2.5 `operation` 已补出最小异常态
`openagentic_case_store_ops` 现在除了 `pending -> applied` 之外，还支持：
- `partially_applied`
- `failed`

并可显式落盘：
- `state.applied_steps`
- `state.failed_steps`

这让 operation 不再只有 happy-path 语义。

### 2.6 `inspection_review` 已补出正式 `reviewing` 过程态
当前 inspect 链路已经改为显式三段：
- 持久化 `pending`
- 持久化 `reviewing`
- 持久化最终 `ready_for_reconsideration | insufficient`

同时 `ext.status_history` 也会保留完整过程轨迹，因此 Round 3 关于“`reviewing` 仅存在于 `process_state` 而非正式状态节点”的结论可以关闭。

## 3. Verification

### 3.1 定向验证
已分别验证：
- `openagentic_case_store_monitoring_run_test`
- `openagentic_case_store_reconsideration_test`
- `openagentic_web_case_governance_reconsideration_test`

对应收口项包括：
- 急报时间线
- operation 异常态
- inspect revision conflict
- versioned reconsideration package
- review status history

### 3.2 全量验证
在 2026-03-09 重新执行：
- `rebar3 eunit`

结果：
- `230 tests, 0 failures`

## 4. Final judgment

**Round 4 的结论是：Round 3 留下的 5 个制度残差已经全部闭合。**

因此现在可以把 Phase 3 的对外表述更新为：
- **主链对齐：完成**
- **结构性差异：完成**
- **细粒度制度残差：完成**
- **全量本地验证：通过**

如果还要继续做下一轮，重点将不再是“设计稿与代码是否对齐”，而是纯粹的人机工效优化，例如：
- 是否要把 `display_code` 做得更短、更像人工编号
- 是否要把 preview 页面再补更多卷宗元信息
- 是否要给 operation 异常态接入更多真实业务调用点
