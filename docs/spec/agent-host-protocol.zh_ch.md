# OpenAgentic 远程 Agent Host 协议（HTTP + SSE）

> 中文说明版。英文规范版见 `docs/spec/agent-host-protocol.md`（建议以英文版为“规范文本”，中文用于解释与取舍记录）。

## 0. 我们到底在解决什么问题？

你提的目标可以概括成一句话：

> “`Subagent` 的**语义不变**（像本地一样用），但执行可以跑在**远端机器**（甚至不同语言实现），并且可观测、可恢复、可控制。”

而我们这个仓库本来就有一个非常关键的前提条件：**session 可 resume**。

- session（`meta.json` + `events.jsonl`）是事实来源（durable log）
- agent 进程只是“执行器/游标”（cursor）

所以把 agent 放到远端，本质上只是把“执行器”放远；只要事件流与 session 仍可被可靠记录/回放，**崩溃恢复**在模型上是成立的。

## 1. 三个决策（你已拍板）

1) 传输：**HTTP + SSE**
2) 发现：**静态配置**（固定 hosts 列表）
3) 鉴权：**pre-shared token**

下面的协议就是围绕这三点，把“来龙去脉 + 设计取舍 + 可落地路径”写清楚。

## 2. 为什么选 HTTP+SSE？

### 优点
- 对代理/反代友好（Caddy/NGINX/Cloudflare 都很常见）
- debug 方便（`curl`/日志就能看清楚发生了啥）
- 符合我们现有的“事件流”抽象（`events.jsonl`）

### 代价
- SSE 是单向（服务端→客户端）：
  - 想 cancel / answer / control，需要额外 HTTP endpoint（`/signal`、`/answer`）

所以协议里会刻意把 **数据面（events）** 和 **控制面（spawn/signal/status）** 分开。

## 3. 为什么先做“静态配置发现”？

你想要“跨语言互相服用”的发现机制，最终可能会走向：

- 中心 registry（带 TTL 心跳）
- gossip
- mDNS

但 v1 先用静态配置有两个决定性好处：

- **可控、安全、可审计**：你明确知道哪台机器在跑 host、用什么 token、允许什么能力
- **不引入额外运维组件**：否则你得先把 registry 也做出来、部署起来、监控起来

静态配置并不妨碍未来升级：协议层不变，只是“如何得到 host 列表”的方式变了。

## 4. 为什么先用 pre-shared token？

这是跨语言最省事的方案：

- Erlang/Kotlin 都容易实现
- 也容易放在反向代理后面

风险在于 token 泄露与轮换，所以协议会建议：

- token 一定要从 env/secret store 来，不要写进配置文件、不要进日志
- 每个 host 独立 token（不要全网共用一个）
- 后续可升级到 mTLS（不影响协议语义，只是换鉴权方式）

## 5. 角色与对象（术语对齐）

- Controller：发起 subagent 的那一侧（你当前 Erlang runtime/CLI）
- Host：提供 HTTP 服务、能运行 agent 的那台机器（可能是 Kotlin 实现）
- Agent：一次可恢复的执行单元（通常绑定一个 session）
- Subagent：被另一个 agent/tool 发起的 agent
- Session：事件日志（`events.jsonl`）+ 元数据（`meta.json`）
- Event：JSON 事件对象（必须带 `type`，并由 store 注入 `seq`、`ts`）

关键点：**跨语言互通的最小公约数就是 events schema**。

## 6. 协议总览（v1）

Base path：`/openagentic/v1`

- `GET  /hello`：握手 + 能力协商
- `POST /agents/spawn`：在 host 上启动 agent（subagent）
- `GET  /agents/{id}/events`：SSE 事件流（核心）
- `GET  /agents/{id}/status`：轮询状态（SSE 不通的兜底）
- `POST /agents/{id}/signal`：cancel/terminate
- `POST /agents/{id}/answer`：给 `user.question` 回答（可选）
- `GET  /artifacts/{id}`：下载大输出（可选但推荐）

鉴权：所有请求都必须带

- `Authorization: Bearer <token>`

## 7. 握手（/hello）到底要交换什么？

目的不是“自动发现”，而是：

- Controller 能知道 host **能干什么/不能干什么**
- 做 host 选择（你将来多台机器时可以按 `tags/capabilities` 选）

建议返回：

- `protocol_version`
- `host_id`
- `impl`（kotlin/erlang + 版本）
- `capabilities`
  - 是否支持 SSE resume（断线重连）
  - 最大并发
  - 是否支持 repo clone
  - 是否允许交互（默认建议不交互）

## 8. Spawn：如何把“初始化提示词 + git clone + 运行约束”传给远端？

Spawn 请求里建议包含三类信息：

1) **链路/追踪信息**（controller/parent）
   - `parent_session_id`
   - `parent_tool_use_id`
   - `trace_id`

2) **agent init 信息**
   - `prompt`
   - `model`
   - `max_steps`
   - `metadata`（例如 purpose=explore）

3) **workspace/repo 信息**
   - `clone_url`
   - `ref`
   - `commit`（可选但强烈建议：可重复构建/可审计）
   - `constraints`（比如 allow_write/allow_network）

注意：

- `constraints` 在 v1 里是“协议层表达”，host 是否强制执行由 host 决定；
- 但我们实现 Erlang Host 时建议尽量强制，尤其是 `allow_write=false` 这种安全约束。

## 9. SSE Events：为什么这是整个协议的核心？

你希望“Subagent 语义不变”，真正不变的是：

- 过程可观测（tool.use/tool.result/runtime.error/result 都能看到）
- 最终能拿到一个明确的 `result.final_text`
- 断线/崩溃能恢复（resume）

SSE 的事件流我们建议直接复用本仓库的 `events.jsonl` 事件对象：

- event JSON 必须包含 `type`
- host 写入 session 时会注入 `seq`（单调递增 int）与 `ts`（float 秒）

SSE 里建议：

- `id:` = `seq`
- `event:` = `type`
- `data:` = JSON

这样断线重连时，客户端只要发：

- `Last-Event-ID: <seq>`

就能让 host 从 `seq+1` 开始重放（如果 host 保留了历史/可从 session 读）。

## 10. 远程 subagent 能不能“纳入监控/监督”？

你问的点非常关键：Erlang 的 supervisor 能不能把远端 subagent 也“监督起来”？

结论要分两种情况：

### 10.1 BEAM ↔ BEAM（两边都是 Erlang/Elixir 节点）
- 可以用分布式 Erlang 的 `monitor` 能力监控远端 pid/节点
- 但经典 supervisor 的语义通常是“监督本地子进程”
- 工程上通常做法：远端自己 supervisor 本地 agent；本地用 monitor/心跳做“逻辑监督”

### 10.2 Erlang ↔ Kotlin（跨语言）
不能用 OTP 原生监督 JVM 内的东西，但可以做到**语义等价**的监督：

- SSE keep-alive + 断线重连
- `/status` 轮询兜底
- lease/timeout
- host 侧基于 session 的 resume（崩溃后重新起进程继续同一 session）

这和你现在的“session 可 resume”思想完全一致，只是监督手段从“进程级”变成“协议级”。

## 10.3 多级互联协作（层级式 subagent）

我们想要的“多级互联”，不应该额外发明第二套协议；正确姿势是让协议天然可组合：

- 任意实现都可以同时扮演 **Host**（提供服务）与 **Controller**（调用别的 Host）
- Host A 上跑的 subagent 也可以再去 spawn Host B/C 上的 subagent（同一套 `/spawn + SSE events`）

建议约定：
- Controller 生成 `trace_id` 并一路透传（方便跨机排错/审计）
- `controller` 字段可以额外带一个 `chain`（纯信息，不影响正确性），用于把调用链串起来

这样“三省六部”也会更自然：每个“省/部”都可以是一个 host 或 host 上的 agent，按制度把任务层层分发与回收。

## 11. “三省六部”多 agent 制度：协议里要预留什么？

三省六部的核心不是“多几个 agent”，而是：

- **角色**（起草/审阅/驳回/增强/实施）
- **规章制度**（哪些可做、哪些必须有证据、哪些必须二次确认）
- **状态机**（Draft→Review→Amend→Approve→Implement→Verify→Deliver）
- **证据链**（events 里能看到每一步做了什么、为什么通过/驳回）

协议层要做的是保证：

- 任何一个远端 agent 的事件都能进入统一事件流（可追溯）
- 远端执行失败能被结构化表达（`runtime.error` / `tool.result is_error=true`）
- 远端结果能被明确收敛（`result.final_text`）

至于“三省六部”的制度本身，可以作为上层 workflow/策略实现（不需要把制度硬写进传输协议里）。

## 12. 分阶段落地（Erlang 先行）

建议按收益/风险排序：

1) Erlang Host：`/hello` + `/spawn` + `/events`（先把远端跑起来、事件流打通）
2) Erlang Controller：实现“RemoteSubagent tool”（spawn + 监听 SSE 到 result）
3) `/signal` cancel + `/status` 兜底
4) artifacts（大输出外置下载）
5) 多级互联：host 同时也能当 controller（协议不变，只是组合方式变）
