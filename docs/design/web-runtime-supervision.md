# Web Runtime 独立监督树关系图

适用版本：2026-03-06（以仓库当前实现为准）

## TL;DR

把 `openagentic web` 的内部服务挂到独立的 OTP supervisor 下面，最大的收益不是“更优雅”，而是：

- 内部子服务崩溃时，不再把启动它的 shell / CLI 调用方一并带死
- `openagentic_web_q` 与 `openagentic_workflow_mgr` 有了稳定、可重启、可观测的宿主
- watchdog 杀掉 workflow runner 时，不会再沿着 link 链误伤 manager，`stalled` 能可靠写回 session
- Web API 可以基于 manager 的状态判断，明确返回 `running` / `queued` / `stalled` / `resumed_from_stalled`

---

## 改造前：调用方与内部服务绑得过紧

```text
Eshell / CLI caller
  |
  +-- openagentic_web:start(...)
        |
        +-- openagentic_web_q
        |
        +-- openagentic_workflow_mgr
              |
              +-- workflow runner (spawn_link)
```

### 旧结构的问题

1. `web` 内部服务的生死，容易跟当前调用方绑在一起。
2. 某个 linked 子进程异常退出时，故障可能沿 link 链向外传播。
3. `workflow runner` 使用 `spawn_link` 时，watchdog 若执行 `exit(Pid, kill)`，manager 也可能被反向带崩。
4. manager 一死，就来不及把 `workflow.done(status=stalled, by=watchdog)` 写进 session；外部只能看到“像卡住了”。

### 故障传播示意

```text
watchdog --kill--> workflow runner
                     |
                     +--(link)--> workflow_mgr
                                      |
                                      +--(link / caller-bound lifecycle)--> shell / CLI
```

这个链路的核心问题是：**服务拓扑与业务拓扑混在了一起**。

---

## 改造后：由独立监督树承接内部服务

```text
Eshell / CLI caller
  |
  +-- start_web_runtime_unlinked / ensure_runtime_started
        |
        +-- openagentic_web_runtime_keeper
              |
              +-- openagentic_web_runtime_sup
                    |
                    +-- openagentic_web_q
                    |
                    +-- openagentic_workflow_mgr

openagentic_web:start(...)
  |
  +-- ensure runtime started
  |
  +-- start Cowboy listener (idempotent)
```

### 新结构的关键点

- `openagentic_web_runtime_keeper` 负责把监督树从“当前调用者的 link 生命周期”中解开。
- `openagentic_web_runtime_sup` 是内部运行时的稳定宿主，统一托管：
  - `openagentic_web_q`
  - `openagentic_workflow_mgr`
- `openagentic_web:start/1` 只负责“确保 runtime 已经起来 + listener 幂等启动”，而不是自己直接承担整个内部服务树。
- CLI 通过非链接包装启动 web runtime，避免 shell 直接成为故障传播链的一部分。

---

## workflow 相关进程关系（改造后）

```text
openagentic_web_runtime_sup
  |
  +-- openagentic_workflow_mgr
        |
        +-- active workflow state / queue / watchdog
        |
        +-- workflow runner (spawn, not link)
                |
                +-- workflow engine step execution
```

### 为什么 runner 改成 `spawn` 很关键

这里真正修到根因的一刀，不只是“加 supervisor”，还包括：

- manager 与 runner 不再用 `spawn_link` 绑定命运
- watchdog 可以安全终止 runner
- manager 仍然活着，能继续：
  - 记录 `stalled`
  - 对外暴露 `status`
  - 接受后续 `continue`
  - 区分普通排队与 `resumed_from_stalled`

换句话说：

- supervisor 解决的是“内部服务不要绑死在 caller 上”
- unlink / non-link runner 解决的是“watchdog 止血时不要误伤 manager”

两者缺一不可。

---

## 状态与恢复语义

独立监督树落地后，Web API 可以更明确地表达 workflow 当前状态：

- `running`：当前 workflow 正在运行
- `queued`：该 workflow 已有运行实例，新的 continue/start 被排队
- `stalled`：watchdog 已止血，运行中断，但 manager 仍活着且状态可见
- `resumed_from_stalled`：本次 `continue` 是从之前的 stalled 状态恢复
- `failed` / `completed`：从 session 中最后一个 `workflow.done` 推断得到

这让前端或调用方不必再通过“看起来没动静”去猜系统是否卡死。

---

## 为什么这比“简单重启一下”更好

如果没有独立监督树，最常见的补丁式修法是：

- 在外层 shell / CLI 再包一层 try-catch
- 子进程死了就粗暴重启一遍
- 依赖上层调用方重新拉起整套 web 服务

这种方式的问题是：

1. 故障边界仍然不清晰。
2. caller 退出时，服务可能一起消失。
3. watchdog / stalled / continue 这些业务语义无处安放。
4. UI 看到的只是“服务断了又起来”，看不到中间业务状态。

独立监督树的价值在于：**先把进程生命线摆正，再谈业务恢复策略**。

---

## 代码落点

- 监督树入口：`apps/openagentic_sdk/src/openagentic_web_runtime_sup.erl`
- Web 启动幂等化：`apps/openagentic_sdk/src/openagentic_web.erl`
- CLI 非链接启动包装：`apps/openagentic_sdk/src/openagentic_cli.erl`
- Workflow 状态与恢复语义：`apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
- Start API 状态输出：`apps/openagentic_sdk/src/openagentic_web_api_workflows_start.erl`
- Continue API 状态输出：`apps/openagentic_sdk/src/openagentic_web_api_workflows_continue.erl`
- Runner 非链接修复与 retry 事件：`apps/openagentic_sdk/src/openagentic_workflow_engine.erl`

---

## 一句话总结

没有独立监督树时，`openagentic web` 更像“挂在当前终端上的一串 linked 进程”；
有了独立监督树后，它才真正变成“由应用自己托管、自己恢复、自己对外报告状态”的运行时系统。
