# Web Supervision + Aggregate Timeout Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 `shangshu_aggregate` 吃旧 prompt、provider timeout 后缺少安全自愈、以及 `openagentic web` 直接链接 shell 导致 `** exception error: killed` 的问题。

**Architecture:** 采用“最小但安全”的修正方案：先把 `shangshu_aggregate` prompt 与 `workspace:staging/<ministry>/poem.md` 新约定对齐；再给 workflow engine 增加**仅针对显式声明的幂等 step**的瞬时 provider 错误自动重试；最后把 web 运行时子服务放进独立 supervisor，避免 `start_link` 直接把 shell 调用进程绑死。坚持“不要全局盲目自愈”，只对无副作用/可重放步骤启用自动恢复。

**Tech Stack:** Erlang/OTP 28, rebar3, Cowboy, EUnit, OpenAI Responses SSE provider

---

## 背景与根因（执行前必须知道）

- 现有 `shangshu_aggregate` prompt 仍是旧版：它还在读取 `workspace:staging/吏部.md` / `户部.md` 等旧命名，并尝试写入 `workspace:deliverables/六部各赋诗一首.md`。这与当前六部 fanout 已统一到 `workspace:staging/<ministry>/poem.md` 的约定冲突。
- provider 层虽然有有限重试（`openagentic_provider_retry.erl`），但 workflow step 层没有“安全的 step 级自动重试”语义；`ProviderTimeoutException` 落到 step 失败时，不会针对“只读/幂等汇总 step”自动重跑。
- `openagentic_web:start/1` 目前直接 `ensure_q_started()` / `ensure_mgr_started()`，内部用 `gen_server:start_link(...)`；当你在 Eshell 里直接执行 `openagentic_cli:main(["web"]).` 时，这些 linked 子进程和当前 shell 调用链绑在一起，异常退出时容易把调用方一起炸成 `killed`。
- `workflow_mgr` 现有 watchdog 更像“止血”：超时就 kill runner 并落 `workflow.done(status=stalled)`，不会自动为当前 step 选择性重启。

---

### Task 1: 修正 `shangshu_aggregate` prompt 契约

**Files:**
- Modify: `workflows/prompts/shangshu_aggregate.md`
- Test: `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl`

**Step 1: 写失败测试，钉住旧 prompt 不再允许出现**

在 `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl` 新增用例，至少断言：
- prompt 包含六部 staging 新路径：
  - `workspace:staging/hubu/poem.md`
  - `workspace:staging/libu/poem.md`
  - `workspace:staging/bingbu/poem.md`
  - `workspace:staging/xingbu/poem.md`
  - `workspace:staging/gongbu/poem.md`
  - `workspace:staging/libu_hr/poem.md`
- 不再出现旧命名：`户部.md`、`礼部.md`、`兵部.md`、`刑部.md`、`工部.md`、`吏部.md`
- 不再强制写 `workspace:deliverables/六部各赋诗一首.md`

**Step 2: 跑测试确认它先红**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`

Expected:
- 新增的 `shangshu_aggregate` prompt 契约测试失败

**Step 3: 最小修改 prompt**

修改 `workflows/prompts/shangshu_aggregate.md`：
- 创作/文案类场景下，汇总 step 只读取 `workspace:staging/<ministry>/poem.md`
- 创作/文案类场景下，允许生成单一合编稿，但写入路径也改为 workflow workspace 下的显式目标；优先先不要求固定 `deliverables` 路径，改为“若需落盘总稿，由任务/方案指定；否则以读取并组织汇总结论为主”
- 明确“尽量不重写原稿，只做合编/校对级变更”
- 减少无关长篇“行动建议”倾向，缩短模型输出压力

**Step 4: 跑测试确认变绿**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`

Expected:
- 新增 prompt 契约测试通过

**Step 5: Commit**

```powershell
git add workflows/prompts/shangshu_aggregate.md apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl
git commit -m "fix: align shangshu aggregate prompt with staging poem paths"
```

---

### Task 2: 为幂等汇总 step 设计显式重试策略（DSL）

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
- Modify: `workflows/three-provinces-six-ministries.v1.json`
- Test: `apps/openagentic_sdk/test/openagentic_workflow_dsl_test.erl`

**Step 1: 写 DSL 失败测试**

在 `apps/openagentic_sdk/test/openagentic_workflow_dsl_test.erl` 增加：
- 一个合法 workflow，step 含例如：
  ```json
  "retry_policy": {
    "transient_provider_errors": true,
    "max_retries": 2,
    "backoff_ms": 1000
  }
  ```
  期望通过校验
- 一个非法 workflow：`max_retries` 为负数或字符串垃圾值，期望校验失败

**Step 2: 跑测试确认先红**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_dsl_test"`

Expected:
- 新增 DSL 测试失败，提示 `unknown keys: retry_policy` 或校验缺失

**Step 3: 最小实现 DSL 扩展**

修改 `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`：
- 允许 step 新字段 `retry_policy`
- 校验子字段：
  - `transient_provider_errors`：bool
  - `max_retries`：非负整数，建议上限 3
  - `backoff_ms`：正整数，建议上限 30000
- 只做 schema + normalize，不在 DSL 层推断是否“安全重试”

**Step 4: 在真实 workflow 上只给 `shangshu_aggregate` 开策略**

修改 `workflows/three-provinces-six-ministries.v1.json`：
- 只给 `shangshu_aggregate` 增加：
  ```json
  "retry_policy": {
    "transient_provider_errors": true,
    "max_retries": 2,
    "backoff_ms": 1000
  }
  ```
- 本轮不要给六部写作 step 开自动重试，避免重复写入副作用

**Step 5: 跑 DSL 测试确认变绿**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_dsl_test"`

Expected:
- 新增 DSL 测试全部通过

**Step 6: Commit**

```powershell
git add apps/openagentic_sdk/src/openagentic_workflow_dsl.erl apps/openagentic_sdk/test/openagentic_workflow_dsl_test.erl workflows/three-provinces-six-ministries.v1.json
git commit -m "feat: add step retry policy for transient provider errors"
```

---

### Task 3: 在 workflow engine 落地“安全自动重试”

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
- Test: `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl`

**Step 1: 写失败测试，先钉住 provider timeout 不会自动恢复**

在 `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl` 增加：
- 一个 workflow，末尾汇总 step 带 `retry_policy`
- fake `step_executor` 第一次返回 provider timeout 风格错误：
  ```erlang
  {error, timeout}
  ```
  或
  ```erlang
  {error, {http_stream_error, timeout}}
  ```
- 第二次返回合法 markdown
- 期望最终 workflow `completed`
- 断言同一 step 至少执行 2 次
- 断言 workflow event log 最终存在 `workflow.step.output` / `workflow.step.pass` / `workflow.done`

再补一个对照测试：
- 没有 `retry_policy` 的 step 遇到同样错误，期望直接失败，不自动重试

**Step 2: 跑测试确认先红**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`

Expected:
- 新增 timeout 自动恢复测试失败

**Step 3: 最小实现 engine 重试**

修改 `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`：
- 增加读取 `retry_policy` 的 helper
- 识别“瞬时 provider 错误”时仅在以下条件下 retry：
  - step 显式声明 `retry_policy.transient_provider_errors = true`
  - 当前错误属于 provider timeout / stream timeout / http stream transient failure
  - 未超过 `max_retries`
- retry 方式：
  - 仍复用同一 workflow step 状态机
  - 在 workflow event 中追加可观测事件（至少记录这是 provider transient retry，以及 attempt/retry 次数）
  - backoff 用 `timer:sleep/1` 或最小统一 helper
- 不要把所有 `executor_failed` 都重试；只重试白名单错误

**Step 4: 修正失败收口，确保 terminal event 一定落盘**

同一文件中顺手补强：
- 当 provider timeout 最终耗尽重试时，必须稳定写入：
  - `workflow.guard.fail` 或等价失败事件
  - `workflow.transition(outcome=fail)`
  - `workflow.done(status=failed)`
- 防止出现“step session 已 error，但 workflow session 没有完整收口”的半死状态

**Step 5: 跑测试确认变绿**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`

Expected:
- timeout 自动恢复测试通过
- 未声明重试策略的对照测试也通过

**Step 6: Commit**

```powershell
git add apps/openagentic_sdk/src/openagentic_workflow_engine.erl apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl
git commit -m "feat: retry idempotent workflow steps on transient provider timeouts"
```

---

### Task 4: 把 `openagentic web` 启动改成可监督、不可误杀 shell

**Files:**
- Create: `apps/openagentic_sdk/src/openagentic_web_runtime_sup.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_cli.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_e2e_online_test.erl`
- Create: `apps/openagentic_sdk/test/openagentic_web_runtime_test.erl`

**Step 1: 写失败测试，先重现当前“link 到调用方”的问题**

新增 `apps/openagentic_sdk/test/openagentic_web_runtime_test.erl`：
- 在单独测试进程里调用 `openagentic_web:start(Opts)`
- 断言返回后，`openagentic_web_q` / `openagentic_workflow_mgr` 存活
- 人工 kill 其中一个子服务（例如 `whereis(openagentic_workflow_mgr)`）
- 期望：测试调用进程本身不因为 linked exit 被杀掉；子服务可由 supervisor 重启或至少由 `openagentic_web:start/1` 隔离在独立树内

**Step 2: 跑测试确认先红**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`

Expected:
- 当前实现下测试失败，表现为 linked exit / 未被监督

**Step 3: 创建 runtime supervisor**

新增 `apps/openagentic_sdk/src/openagentic_web_runtime_sup.erl`：
- `one_for_one` supervisor
- children 至少包含：
  - `openagentic_web_q`
  - `openagentic_workflow_mgr`
- 仅负责 web runtime 内部服务，不负责 Cowboy listener

**Step 4: 修改 `openagentic_web:start/1` 用 supervisor 启动内部服务**

修改 `apps/openagentic_sdk/src/openagentic_web.erl`：
- 不再在 `start/1` 里直接 `start_link` 子 gen_server
- 改为确保 `openagentic_web_runtime_sup` 存在
- `start/1` 只负责：
  - 启动/复用 runtime supervisor
  - 启动 Cowboy listener
- 如已启动，保持幂等

**Step 5: 让 CLI `web` 分支不把 shell 自己绑成脆弱父进程**

修改 `apps/openagentic_sdk/src/openagentic_cli.erl`：
- 维持 `openagentic_cli:main(["web"])` 的当前 UX，不改命令格式
- 但要避免“web 内部服务异常 -> 直接把 Eshell 调用进程带崩”的链路
- 若需要，可在 CLI 层加最小 trap_exit / 非链接包装，但优先把根因修在 supervisor 结构上

**Step 6: 跑 web 相关测试确认变绿**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`

再跑：
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_e2e_online_test"`

Expected:
- runtime supervisor 测试通过
- 现有 web e2e 不回归

**Step 7: Commit**

```powershell
git add apps/openagentic_sdk/src/openagentic_web_runtime_sup.erl apps/openagentic_sdk/src/openagentic_web.erl apps/openagentic_sdk/src/openagentic_cli.erl apps/openagentic_sdk/test/openagentic_web_runtime_test.erl apps/openagentic_sdk/test/openagentic_web_e2e_online_test.erl
git commit -m "fix: supervise web runtime services independently from shell caller"
```

---

### Task 5: 明确 `workflow_mgr` 的“止血 vs 自愈”边界，并补状态可见性

**Files:**
- Modify: `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_workflows_continue.erl`
- Modify: `apps/openagentic_sdk/src/openagentic_web_api_workflows_start.erl`
- Test: `apps/openagentic_sdk/test/openagentic_web_runtime_test.erl`

**Step 1: 写失败测试，钉住 stalled 的可见性**

新增/补充测试：
- 当 watchdog kill 一个 runner 后，session 中应追加明确的 `workflow.done(status=stalled, by=watchdog)`
- Web API 再次 `continue` 时，响应中应能区分：
  - 是普通继续
  - 还是从 `stalled` 状态恢复

**Step 2: 跑测试确认先红**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`

Expected:
- stalled 状态可见性不足导致测试失败

**Step 3: 最小增强 manager / API**

修改 `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl` 与两个 web API handler：
- 保持当前“watchdog 默认不盲目自动重启”的保守策略
- 但补出更清晰的状态：
  - `stalled`
  - `failed`
  - `queued`
  - `resumed_from_stalled`（如果是手工 continue 恢复）
- 让前端/调用方一眼知道当前状态，而不是只看到“像卡住了”

**Step 4: 跑测试确认变绿**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`

Expected:
- stalled / resumed 状态可见性测试通过

**Step 5: Commit**

```powershell
git add apps/openagentic_sdk/src/openagentic_workflow_mgr.erl apps/openagentic_sdk/src/openagentic_web_api_workflows_start.erl apps/openagentic_sdk/src/openagentic_web_api_workflows_continue.erl apps/openagentic_sdk/test/openagentic_web_runtime_test.erl
git commit -m "feat: expose stalled and resumed workflow states clearly"
```

---

### Task 6: 全量回归与文档同步

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/plans/2026-03-06-web-supervision-and-aggregate-recovery-plan.md`

**Step 1: 跑定向测试**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_dsl_test"`

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`

**Step 2: 跑全量回归**

Run:
`pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit"`

Expected:
- 全绿

**Step 3: 同步文档与运行约定**

更新 `AGENTS.md`：
- 增补“web runtime 由独立 supervisor 托管”的约定
- 增补“仅显式声明的幂等 step 才允许自动重试”的约定
- 保持 `E:\openagentic-sdk\sessions` 会话目录说明不丢

**Step 4: 回写计划证据**

在本计划文档末尾补：
- 实际落地文件
- 运行过的命令
- 关键输出摘要
- 是否还有未做项

**Step 5: Commit**

```powershell
git add AGENTS.md docs/plans/2026-03-06-web-supervision-and-aggregate-recovery-plan.md
git commit -m "docs: record aggregate recovery and web supervision plan evidence"
```

---

## 实施原则（执行时必须遵守）

- 不做“全局自动重试所有 step”的危险设计。
- 只对显式声明 `retry_policy` 的 step 启用自动重试。
- `Write/Edit/Bash/Task` 等可能有副作用的步骤，本轮默认不自动重跑。
- 先补失败测试，再改代码；任何“看起来显然正确”的修复也必须有红灯到绿灯证据。
- `openagentic web` 必须改为 OTP 风格监督结构，不能再依赖 Eshell 调用进程的生命线。

## DoD

- `shangshu_aggregate` prompt 完全对齐 `workspace:staging/<ministry>/poem.md`
- `shangshu_aggregate` 遇到瞬时 provider timeout 时可安全自动重试并最终收口
- `openagentic web` 不再因 linked 子服务异常把 Eshell 调用方炸成 `killed`
- `workflow_mgr` 的 `stalled` 状态对 API / UI 可见
- `rebar3 eunit` 全绿

---

## Execution Evidence / 实际落地证据

### 实际落地文件

- `workflows/prompts/shangshu_aggregate.md`
- `workflows/three-provinces-six-ministries.v1.json`
- `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
- `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
- `apps/openagentic_sdk/src/openagentic_web_runtime_sup.erl`
- `apps/openagentic_sdk/src/openagentic_web.erl`
- `apps/openagentic_sdk/src/openagentic_cli.erl`
- `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
- `apps/openagentic_sdk/src/openagentic_web_api_workflows_start.erl`
- `apps/openagentic_sdk/src/openagentic_web_api_workflows_continue.erl`
- `apps/openagentic_sdk/test/openagentic_workflow_dsl_test.erl`
- `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl`
- `apps/openagentic_sdk/test/openagentic_web_runtime_test.erl`
- `AGENTS.md`

### 实际运行命令

- `pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_dsl_test"`
- `pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_workflow_engine_test"`
- `pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_runtime_test"`
- `pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit -m openagentic_web_e2e_online_test"`
- `pwsh -Command ". .\scripts\erlang-env.ps1 -SkipRebar3Verify ; rebar3 eunit"`

### 关键输出摘要

- `openagentic_workflow_dsl_test`：通过，覆盖 `retry_policy` 合法配置与非法参数拒绝。
- `openagentic_workflow_engine_test`：通过，覆盖 `shangshu_aggregate` 新 prompt 路径与 transient provider retry 行为。
- `openagentic_web_runtime_test`：通过，覆盖 web runtime supervisor 隔离、watchdog stalled 可见性、`continue` 的 `queued` / `resumed_from_stalled` 状态。
- `openagentic_web_e2e_online_test`：当前无在线用例执行，未见回归。
- `rebar3 eunit`：`153 tests, 0 failures`。

### 未做项 / 说明

- 计划中的 `git commit` 未执行；原因是当前会话的上层开发约束明确禁止代理自行提交。
- 全量 `rebar3 eunit` 结束后仍会出现仓库既有的 `io:format(otp_release...)` / `erl_scan illegal,string` 噪音文本，但退出码为 `0`，且测试统计全绿，本次未将其视为回归。
