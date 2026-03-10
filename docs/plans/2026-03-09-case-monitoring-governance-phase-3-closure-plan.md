# Phase 3 Closure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Phase 3 从“第一版可运行闭环”收口到“与 PRD 基本对齐”的状态，重点补齐 adoption 回链、deferred 门禁、复议上下文装配、卷宗内容语义与规则执行化。

**Architecture:** 保留现有 `openagentic_case_store_api_reconsideration` 作为 Phase 3 主 orchestrator，不推翻已有对象模型与 Web 路径。`P0` 只补制度硬约束与关系回链，`P1` 补冻结卷宗与预览语义，`P2` 再把规则执行化与文档/索引硬化收口。若 `api_reconsideration` 在 `P2` 开始变得过重，再把 readiness / start gate 规则抽到独立 helper 模块，而不是在 `P0/P1` 提前大拆文件。

**Tech Stack:** Erlang/OTP 28、Cowboy、EUnit、本地 JSON 持久化、`openagentic_session_store`、静态 Web UI。

**Repo Note:** 受仓库约束影响，本计划不包含 `git commit` 步骤；每个任务以“定向验证 + 全量 `rebar3 eunit`”作为收口动作。

---

## Priority Split

### P0：制度硬约束，必须先补
- 回填 `inspection_review.links.derived_briefing_id`
- 启动复议前重新校验 `deferred / superseded / stale`
- 把卷宗快照真正装配进新复议 session 的上下文

### P1：卷宗内容与阅卷体验
- 扩充 `frozen_payload`，冻结上一轮结论、基线事实、变化事实与变化分类
- 扩充预览 API / 页面，真正展示 controversies 与生命周期提示

### P2：规则执行化与硬化
- 让 `completeness_rule / inspection_rule / trigger_policy` 进入可执行逻辑
- 稳定对象回链、overview/indexes 与 README / 中文 README / 审计文档

---

### Task 1: P0.1 回填 review → package adoption 回链

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: 先写失败测试（store 层）**

在 `observation_pack_review_and_reconsideration_snapshot_test/0` 创建卷宗后，追加断言：

```erlang
ReviewAfter = openagentic_case_store_case_state:get_case_overview_map(Root, CaseId),
?assertEqual(PackageId, deep_get(lists:last(maps:get(inspection_reviews, ReviewAfter)), [links, derived_briefing_id])).
```

**Step 2: 运行定向测试，确认现在会失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: 失败在 `derived_briefing_id` 仍为 `undefined`。

**Step 3: 做最小实现**

在 `create_reconsideration_package_ready/7` 中：

- 生成 `Package` 后，立刻更新对应 `Review`；
- 将 `links.derived_briefing_id => PackageId` 回填；
- 持久化更新后的 `inspection_review`；
- 保持 `Pack.links.current_inspection_review_id` 不变，不要改对象主关系。

**Step 4: 补一条 API 级回归断言**

在 `openagentic_web_case_governance_reconsideration_test.erl` 创建卷宗后，通过 overview 或返回对象断言该字段已回填，防止只有 store 层对齐、API 返回遗漏。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: PASS。

---

### Task 2: P0.2 为 `start_reconsideration/2` 增加 deferred / stale / superseded 门禁

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_action.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: 先写失败测试（store 层）**

新增两组断言：

```erlang
?assertMatch({error, reconsideration_package_superseded},
  openagentic_case_store:start_reconsideration(Root, #{case_id => CaseId, package_id => OldPackageId, started_by_op_id => <<"lemon">>})).

?assertMatch({error, reconsideration_package_stale},
  openagentic_case_store:start_reconsideration(Root, #{case_id => CaseId, package_id => DeferredPackageId, started_by_op_id => <<"lemon">>})).
```

测试构造建议：

- superseded：先 defer 第一版卷宗，再生成第二版，然后尝试启动第一版；
- stale：把相关 `fact_report.state.submitted_at` 或 `Package.state.freshness_checked_at` 调整为过期值，再尝试启动 defer 的卷宗。

**Step 2: 运行定向测试，确认失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: 旧逻辑会错误地允许 `ready|deferred` 直接启动。

**Step 3: 做最小实现**

在 `start_reconsideration/2` 前增加统一 gate：

- 拒绝 `state.status = superseded`；
- 若 `state.status = deferred`，重新读取 pack / review / reports；
- 用当前时间重新校验 freshness；
- 若已有更新版卷宗替代当前卷宗，返回 `reconsideration_package_superseded`；
- 若 freshness 失败，返回 `reconsideration_package_stale`；
- 只有 `ready` 或“仍有效的 deferred”才允许继续。

错误映射建议：

- `reconsideration_package_not_actionable`
- `reconsideration_package_superseded`
- `reconsideration_package_stale`

都在 Web action handler 中映射为 `409`，而不是 `500`。

**Step 4: 补 API 级失败用例**

在 `openagentic_web_case_governance_reconsideration_test.erl` 追加：

- 启动 superseded 卷宗返回 `409`；
- 启动 stale deferred 卷宗返回 `409`。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: PASS。

---

### Task 3: P0.3 把卷宗快照装配进新复议 session 的上下文

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_support.erl`
- Optional Modify: `apps/openagentic_sdk/src/openagentic_session_store/openagentic_session_store_append.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Step 1: 先写失败测试**

在 `reconsideration_package_deferred_superseded_and_consumed_test/0` 启动复议后追加断言：

- 新 round 的 `workflow_session_id` 对应 session 存在；
- 该 session 的 `meta.json` 或首条 `system.init` 事件里包含 `reconsideration_context`；
- `reconsideration_context.package_id = Package1Id`；
- `reconsideration_context.frozen_payload.summary` 非空。

**Step 2: 运行定向测试，确认失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: 当前新 session 只有默认元数据，没有卷宗快照上下文。

**Step 3: 做最小实现**

推荐实现：

- `create_session/2` 时，把 `#{reconsideration_context => #{package_id => ..., package_display_code => ..., frozen_payload => ...}}` 放入 metadata；
- 紧接着 append 一条 `system.init`，把同样的 `reconsideration_context` 放在 `Extra` 里；
- 不要把整个历史 transcript 复制进去，只注入 `frozen_payload` 和最小必要 refs。

若 metadata 足够表达，不要为了这一项改 session store layout；只有在读取困难时再动 `openagentic_session_store_append.erl`。

**Step 4: 补一条可追索辅助字段**

建议在 `Round.ext` 或 `Round.audit` 中追加 `context_source => reconsideration_package`，便于后续调试“本轮为什么能开起来”。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: PASS。

---

### Task 4: P1.1 扩充 `frozen_payload` 的卷宗语义

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_support.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Step 1: 先写失败测试**

为 `FrozenPayload` 增加期望字段断言：

```erlang
?assertMatch(#{summary := _}, FrozenPayload),
?assertMatch(#{based_on_round := _}, FrozenPayload),
?assertMatch(#{baseline_facts := _}, FrozenPayload),
?assertMatch(#{change_facts := _}, FrozenPayload),
?assertMatch(#{controversies := _}, maps:get(summary, FrozenPayload)).
```

**Step 2: 运行定向测试，确认失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: 当前 `frozen_payload/4` 只有 case/pack/review/reports/summary 的轻量版本。

**Step 3: 做最小实现**

在 `frozen_payload/4` 附近新增 helper，补齐：

- `based_on_round`：冻结上一轮 `round_id`、`workflow_session_id` 与 `workflow.done` 摘要；
- `baseline_facts`：上一轮仍成立、且本轮继续作为背景的最小事实；
- `change_facts`：来自本轮报告、值得推动复议的变化事实；
- `change_categories`：至少分 `new_signal`、`confirmed_signal`、`contradiction`、`risk_escalation`；
- `controversies`：从 `Review.spec.controversy_candidates` 冻结正文，而不只保存 id/title。

实现优先级建议：

- 先把字段结构补齐；
- 再用保守规则从现有 report summary / workflow.done 文本里组装；
- 不要在这个阶段引入复杂 NLP。

**Step 4: 保持向后兼容**

`preview` API 仍返回 `preview => FrozenPayload`，旧字段继续保留，避免 UI 在中途断掉。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: PASS。

---

### Task 5: P1.2 扩充预览 API 与预览页内容密度

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_preview.erl`
- Modify: `apps/openagentic_sdk/priv/web/view/reconsideration-preview.html`
- Modify: `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- Modify: `apps/openagentic_sdk/priv/web/assets/inbox.js`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_static_page_test.erl`

**Step 1: 先写失败测试**

为静态页与 API 增加断言：

- HTML 中存在 controversies、baseline、changes、lifecycle hint 容器；
- preview API 返回这些字段；
- defer 后再次打开 preview，能看到 `deferred` 生命周期提示；
- superseded 的旧卷宗 preview 会显示“已被新版替代”。

**Step 2: 运行定向测试，确认失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_web_case_governance_reconsideration_test --module=openagentic_web_case_governance_static_page_test
```

Expected: 当前页面只展示标题、报告数量、简单列表，缺少新容器与提示文案。

**Step 3: 做最小实现**

页面至少新增这几块：

- `卷宗基线`：上一轮结论 / 最小背景事实；
- `本轮变化`：变化事实与分类；
- `争议清单`：正文摘要，而不是只显示数量；
- `生命周期提示`：当前是否 `ready / deferred / superseded / consumed_by_round`；
- `纳入依据`：本次卷宗包含哪些报告、为什么纳入。

`reconsideration-preview.js` 中把按钮状态与提示文案也一起收口：

- `superseded` 时禁用 `开启复议`；
- `consumed_by_round` 时显示已开启的 round id；
- `deferred` 时显示“继续观察中，可在新鲜期内重新发起”。

**Step 4: 保持 inbox 入口稳定**

Inbox 中的 `查看卷宗` 链接继续使用 `preview_url`，不改已有入口格式，只增强目的页内容。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_web_case_governance_reconsideration_test --module=openagentic_web_case_governance_static_page_test
```

Expected: PASS。

---

### Task 6: P2.1 让 pack/review 规则从“字段”升级为“执行化逻辑”

**Status:** [x] Completed on 2026-03-09

**Files:**
- Create: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_reconsideration_rules.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Step 1: 先写失败测试**

补三类规则测试：

- `completeness_rule`：允许 `all_required_reports_present` 与最小数量阈值；
- `inspection_rule`：允许 `manual_inspection_required` 与“必须存在 controversies / 必须不存在 blocking_issues”这类 gate；
- `trigger_policy`：允许 `manual` 与“达到 ready 但不自动生成卷宗”的语义保持清晰。

**Step 2: 运行定向测试，确认失败**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: 当前逻辑主要只按 freshness + required report 存在与否来算。

**Step 3: 做最小实现**

新建 `openagentic_case_store_reconsideration_rules.erl`，集中放：

- `evaluate_completeness_rule/3`
- `evaluate_inspection_rule/2`
- `can_start_deferred_package/4`

`api_reconsideration` 只保留 orchestration，把规则判断委托给 helper 模块。这样可以避免该文件继续膨胀。

**Step 4: 重新走一遍已有主链**

确保已有默认值仍兼容：

- 未显式指定规则时，行为与今天一致；
- 只是从“散落 if/else”升级成“默认规则 + 可扩展执行器”。

**Step 5: 重新验证**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: PASS。

---

### Task 7: P2.2 稳定索引、总览与文档对齐

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
- Modify: `README.md`
- Modify: `README.zh_ch.md`
- Modify: `docs/plans/2026-03-09-case-monitoring-governance-phase-3-alignment-audit.md`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: 先写一条总览回归断言**

确保 overview 始终能稳定呈现：

- `observation_packs`
- `inspection_reviews`
- `reconsideration_packages`
- package 生命周期状态分组

并验证 Phase 派生逻辑不会因为新增状态而乱跳。

**Step 2: 做最小实现**

检查 `openagentic_case_store_case_state.erl`：

- `derive_case_phase/2` 与 `group_ids_by_status/1` 是否覆盖新增错误态；
- overview 与 index 文件是否包含 Phase 3 所需状态；
- 如有必要，把 superseded / deferred / consumed 状态映射写清楚。

**Step 3: 更新对外文档**

把 README 与中文 README 中关于 Phase 3 的表述，从“第一版闭环”更新为“带 adoption 回链、deferred 门禁、预览增强、session 上下文装配”的真实状态。

同步更新审计文件，把已收口项从缺口中移走，避免文档继续漂移。

**Step 4: 跑相关测试**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_web_case_governance_reconsideration_test --module=openagentic_web_case_governance_static_page_test
```

Expected: PASS。

---

## Final Verification Gate

完成全部任务后，统一执行：

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit
```

Expected:

- `0 failures`
- Phase 3 store / API / static page tests 全绿
- 没有把现有 Phase 1 / Phase 2 主链打断

---

## Recommended Execution Order

1. `Task 1`：先补 adoption 回链，最小且无争议
2. `Task 2`：补 start gate，防止制度漏洞继续扩散
3. `Task 3`：补 session 上下文装配，完成“默认读卷宗”关键语义
4. `Task 4`：扩充冻结卷宗内容
5. `Task 5`：把新卷宗内容透出到预览页
6. `Task 6`：抽规则模块，做执行化升级
7. `Task 7`：统一 README / 审计文档 / indexes 收尾

按这个顺序推进，能保证每一步都建立在上一层已经稳定的制度语义之上，不会出现“UI 先展示了一堆其实后端还没冻结的字段”。
