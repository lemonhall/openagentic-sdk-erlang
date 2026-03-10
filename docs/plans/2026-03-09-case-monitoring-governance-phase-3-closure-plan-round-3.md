# Phase 3 Round 3 Closure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把第二轮审计发现的 5 类剩余差异收口掉，让 Phase 3 从“核心闭环已完成”进一步推进到“制度层 / 架构层也基本对齐设计稿”。

**Architecture:** 本轮不重做 Phase 3 主链，而是在现有 `openagentic_case_store_api_reconsideration` 周边补三类横切能力：一是显式 `operation` 与 `timeline` 派生层；二是 Phase 3 的并发保护与急报分支；三是把 inspection 从结果快照扩成轻量过程态机。新增能力优先抽成独立 helper / object family，避免继续把 `api_reconsideration` 做成大泥球。

**Tech Stack:** Erlang/OTP 28、Cowboy、EUnit、本地 JSON 持久化、append-only history、case indexes、静态 Web UI。

**Repo Note:** 本计划不包含 `git commit`；每个任务以“定向验证 + 最终 `rebar3 eunit`”收口。执行时继续使用 `pwsh.exe`，不要回退到 `powershell.exe` 5.x。

---

## Priority Split

### P0：先补治理真相层
- Phase 3 跨对象动作显式 `operation` 落盘
- `timeline.jsonl` 里程碑时间线补齐

### P1：补制度分支与并发保护
- Phase 3 Web / store 动作接入 revision gate
- `urgent_brief` / 重大异常急报主链落地

### P2：补 inspection 过程态
- 把 `inspection_review` 从“终态快照”扩成“轻量过程态机”

---

### Task 1: P0.1 为 Phase 3 动作引入显式 `operation` 落盘

**Status:** [x] Completed on 2026-03-09

**Files:**
- Create: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_ops.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_repo_paths.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Step 1: Write the failing store test**

在 `openagentic_case_store_reconsideration_test.erl` 增加一条链路断言：

```erlang
OperationPath = filename:join([CaseDir, "meta", "ops", ensure_list(OpId) ++ ".json"]),
?assert(filelib:is_file(OperationPath)),
Operation = openagentic_case_store_repo_persist:read_json(OperationPath),
?assertEqual(<<"start_reconsideration">>, deep_get(Operation, [spec, op_type])).
```

至少覆盖三个动作：
- `create_reconsideration_package`
- `defer_reconsideration_package`
- `start_reconsideration`

**Step 2: Run test to verify it fails**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: FAIL，因为当前没有 `meta/ops/*.json` 落盘。

**Step 3: Write minimal implementation**

实现一个轻量 `operation` helper：

- `new_operation/4`
- `mark_applied/3`
- `persist_operation/2`

对象建议字段：

- `header.type = <<"operation">>`
- `spec.op_type`
- `links.case_id`
- `state.status`
- `state.applied_steps`
- `state.failed_steps`
- `audit.initiator_op_id`

并在三条 Phase 3 动作链里分别落盘：

- 出卷宗
- defer 卷宗
- start 复议

`internal_mail.links.source_op_id` 也同步回填。

**Step 4: Run test to verify it passes**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: PASS。

---

### Task 2: P0.2 补 `timeline.jsonl` 里程碑时间线

**Status:** [x] Completed on 2026-03-09

**Files:**
- Create: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_timeline.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_repo_paths.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`

**Step 1: Write the failing store test**

新增断言：

```erlang
TimelinePath = filename:join([CaseDir, "meta", "timeline.jsonl"]),
?assert(filelib:is_file(TimelinePath)),
Entries = read_jsonl(TimelinePath),
?assert(lists:any(fun(E) -> deep_get(E, [event_type]) =:= <<"reconsideration_package_deferred">> end, Entries)).
```

至少覆盖这些里程碑：
- `observation_pack_ready`
- `reconsideration_package_created`
- `reconsideration_package_deferred`
- `reconsideration_package_superseded`
- `reconsideration_round_started`

**Step 2: Run test to verify it fails**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: FAIL，因为当前没有 `timeline.jsonl`。

**Step 3: Write minimal implementation**

增加 best-effort timeline helper：

- `append_event/3`
- `event_shell/4`

事件外壳至少包含：

- `event_id`
- `event_type`
- `case_id`
- `created_at`
- `summary`
- `related_object_refs`
- `op_id`

注意：timeline 失败不能阻断主业务动作，只能吞掉并保持主对象写入成功。

**Step 4: Run test to verify it passes**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test
```

Expected: PASS。

---

### Task 3: P1.1 为 Phase 3 关键动作接入 `revision` 乐观并发 gate

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_packages_create.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_reconsideration_package_action.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: Write the failing tests**

补两类测试：

1. store 层：

```erlang
?assertMatch(
  {error, {revision_conflict, _}},
  openagentic_case_store:defer_reconsideration_package(Root, #{case_id => CaseId, package_id => PackageId, current_revision => 0})
).
```

2. web 层：

```erlang
{409, Conflict} = http_post_json(...),
?assertEqual(<<"revision_conflict">>, maps:get(<<"error">>, Conflict)).
```

至少覆盖：
- `create_reconsideration_package`
- `defer_reconsideration_package`
- `start_reconsideration`

**Step 2: Run tests to verify they fail**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: FAIL，因为当前 Phase 3 未校验 `current_revision`。

**Step 3: Write minimal implementation**

新增一个小 helper，例如：

- `require_revision/3`

语义：
- 若未传 `current_revision`，默认兼容旧调用；
- 若传了，则必须与对象当前 `header.revision` 一致；
- 不一致返回 `{error, {revision_conflict, CurrentRevision}}`。

Web handler 对应映射 `409`。

**Step 4: Run tests to verify they pass**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: PASS。

---

### Task 4: P1.2 补 `urgent_brief` / 重大异常急报主链

**Status:** [x] Completed on 2026-03-09

**Files:**
- Create: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_urgent_brief.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_run_finalize_success.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: Write the failing tests**

设计一个 provider fixture，让报告返回明确的 urgent signal，例如：

```erlang
alert_summary => <<"Major escalation detected">>,
alert_severity => <<"high">>
```

断言：
- 运行成功后生成一封急报 mail；
- 生成一个 `urgent_brief` 对象；
- 后续出卷宗时 `included_urgent_refs` 不再为空。

**Step 2: Run tests to verify they fail**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: FAIL，因为当前没有急报对象家族。

**Step 3: Write minimal implementation**

先做最小版本：

- 新增 `urgent_brief` 对象落盘；
- 由 run finalize success 在命中阈值时创建；
- 生成一封 `message_type = <<"urgent_brief">>` 的内邮；
- `create_reconsideration_package/2` 读取当前相关 urgent briefs，填入 `included_urgent_refs`。

不要在这一轮里把急报自动替代 observation pack；只做“急报提醒 + 卷宗可引用”。

**Step 4: Run tests to verify they pass**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: PASS。

---

### Task 5: P2.1 把 inspection 从“结果快照”扩成“轻量过程态机”

**Status:** [x] Completed on 2026-03-09

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_api_reconsideration.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_case_store/openagentic_case_store_case_state.erl`
- Modify: `apps/openagentic_sdk/priv/web/assets/reconsideration-preview.js`
- Test: `apps/openagentic_sdk/test/openagentic_case_store_reconsideration_test.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_case_governance_reconsideration_test.erl`

**Step 1: Write the failing tests**

补两层断言：

1. store 层：
- 初次生成 review 时，先写 `pending` 或 `reviewing` 过渡态；
- 最终再落到 `ready_for_reconsideration` / `insufficient`。

2. web 层：
- preview / overview 至少能稳定显示新的 review 状态，不因为新增态崩溃或误判 phase。

**Step 2: Run tests to verify they fail**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: FAIL，因为当前 inspect 直接产出终态。

**Step 3: Write minimal implementation**

建议最小策略：

- review 对象先以 `pending` 创建；
- 完成 `evaluate_*` 后同一次调用内更新为最终态；
- 或者显式引入 `reviewing` 过渡态并保留 history；
- 保持对外 API 兼容，不强制引入异步检察 worker。

这里的重点不是做异步系统，而是把“过程态存在且可追索”补齐。

**Step 4: Run tests to verify they pass**

Run:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_reconsideration_test --module=openagentic_web_case_governance_reconsideration_test
```

Expected: PASS。

---

## Final Verification Gate

全部任务完成后，统一执行：

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit
```

Expected:

- `0 failures`
- Phase 3 的 store / web / timeline / urgent / revision / inspection tests 全绿
- 不打断既有 Phase 1 / Phase 2 / 已收口的 Phase 3 主链

---

## Done Definition

只有在以下条件同时满足时，第三轮才算完成：

1. `operation` 已正式落盘，且 mail / action 可回溯 `source_op_id`
2. `timeline.jsonl` 已存在并记录 Phase 3 里程碑事件
3. Phase 3 关键动作支持 `revision_conflict`
4. `urgent_brief` 已形成对象 + mail + 卷宗引用闭环
5. `inspection_review` 不再只有终态快照，至少具备可追索过程态
6. `rebar3 eunit` 全量通过
7. README / 中文 README / 审计文档如有对外语义变化，则同步更新

