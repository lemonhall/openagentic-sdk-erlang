# 2026-03-06：论证题证据增强与 Tavily Extract 接管 WebFetch 的交接文档

## 背景

本轮上下文来自 `three-provinces-six-ministries.v1` 的多个会话，核心参考会话为：
- `workflow_session_id=4748335c558e699352bb27b4ae06ecd7`

用户对该 session 的总体评价：
- **整体质量较高**。
- 六部各自的论证方式、论证骨架、推演路径、分阶段展开，**本身是好的**。
- 用户**不是**要把整类任务改成“整体轻量 research”。
- 用户要的是：**在论证题里，当某一条论据需要事实佐证、具体数字、时间线、公开信号时，让该部自己的 agent 可以启动一个 subagent / deep-research 式的证据收集动作，给这一条论证补证据，而不是把整篇都改写成 research 报告。**

## 用户的最终意图（必须严格按这个理解）

### 1）不要破坏当前六部的高质量论证骨架
保留：
- 六部各自从本部视角出发
- 自己下判断
- 自己展开理由、路径、过程
- 分阶段推演
- 最后仍是尚书省汇总、太子回奏

不要改成：
- 整个任务都变成“研究报告体”
- 六部不再自己论证，只会贴来源
- 六部输出变成大段 `Sources`、引用堆砌、失去原本论证张力

### 2）只在“某一条论据需要事实/数字支撑”时触发证据增强
触发场景包括但不限于：
- 需要具体时间线
- 需要公开数字
- 需要公开表态
- 需要某项事实是否已广泛报道
- 需要公开可观察信号来支撑某个推演分支
- 需要用权威公开来源补强“这条论据为什么成立”

非目标：
- 不是让整篇全文默认都去联网
- 不是让每个段落都去搜来源
- 不是让模型一上来先做核验闭环、把正文拖死

### 3）证据增强应当嵌入原有论证，而不是替代原有论证
正确形态：
- 原有论证主干仍由六部自己写
- 在某条关键论据下，补 1~3 条事实、数字、公开信号或公开报道作为支撑
- 证据是“给论据加骨架”，不是“拿来源替代思考”

错误形态：
- 全文改写成 `Executive Summary / Key Findings / Sources` 那一套
- 六部不再论证，只会堆外链
- 因为要证据就把整体文风搞散

## 对 `deep-research` 的正确借鉴方式

用户明确提到要参考 `$deep-research`，但**不是照抄它的全文结构**。

应借鉴的是它的方法：
- 有意识地拆出“哪些点需要证据”
- 主动搜索公开来源
- 抓取并整理可引用事实/数字/时间线
- 区分已知、争议、未知
- 把证据嵌回原有分析

不应借鉴的是：
- 把六部原有文稿整体改造成 deep-research 报告模板

一句话：
> 借鉴 deep-research 的“取证方法”，不要替换六部现有的“论证写法”。

## 对 workflow / prompts 的目标修改方向

### 中书省 / 尚书省
后续 prompt 修改方向应是：
- 不要把“论证题”整体改写成“轻量 research 任务”
- 而是把要求写成：
  - **保留六部原有论证骨架**
  - 当某条论据需要公开事实、数字、时间线、公开信号时，允许并鼓励该部 agent 启动一轮 subagent / deep-research 式取证
  - 取证结果用于补强该条论据，不改变整篇文风与结构主轴

### 六部 prompt
后续 prompt 修改方向应是：
- 在各部 prompt 中新增一条类似约束：
  - 当一条论据需要事实/数字/时间线/公开信号支撑时，可启动一轮小型取证动作
  - 取证完成后，把证据回填到该论据下
  - 不要把整篇改写成 research 报告
- 取证产物建议尽量短：
  - 1~3 条事实
  - 1~3 个关键数字或时间线节点
  - 1~3 个可引用公开来源
- 最终正文仍以本部论证为主，不以来源堆砌为主

### 关于 subagent
用户明确希望：
- 六部自己的 agent 在必要时，**可以启动一个 subagent**
- 该 subagent 干的事，本质上是一次小型 deep-research / evidence collection

待下一任确认的问题：
- workflow 当前实际暴露给 step agent 的工具里，`Task` / subagent 能力是否已经可用
- 若可用：优先走 `Task` 子代理
- 若不可用：则先用本 agent 直接调用 `WebSearch/WebFetch` 模拟一轮小型取证，但文档与 prompt 仍按“subagent 式取证”来设计

## 对 `WebFetch` 的最终要求

用户明确要求：
- 不要再用 reader 之类的其它兜底方案
- **只使用 Tavily Extract** 作为 `WebFetch` 的反爬/JS 壳兜底

### 具体要求
1. `WebFetch` 仍然先尝试直接抓站点正文
2. 如果遇到以下情况，应自动转 Tavily Extract：
   - 只拿到 “Please enable JS”
   - 只拿到 “Just a moment...”
   - 403 / 401 / 429 之类明显拦截
   - Cloudflare / 反爬壳 / 空正文 / 占位页
3. 不要引入 reader 兜底
4. 可以直接用 Erlang 实现 Tavily Extract 的 HTTP API 调用，不必依赖 Python 运行时
5. 如果后续确实为了本地实验要用 Python 包，也应只作为临时验证，不应成为正式 runtime 依赖

## 用户给出的 Tavily Extract API 形态（后续实现以此为准）

用户明确给出了这段调用形态：

```bash
curl --request POST \
  --url https://api.tavily.com/extract \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '
{
  "urls": "https://en.wikipedia.org/wiki/Artificial_intelligence",
  "query": "<string>",
  "chunks_per_source": 3,
  "extract_depth": "basic",
  "include_images": false,
  "include_favicon": false,
  "format": "markdown",
  "timeout": "None",
  "include_usage": false
}
'
```

因此后续实现建议：
- 直接在 `openagentic_tool_webfetch.erl` 里加 Tavily Extract fallback
- 鉴权用：`Authorization: Bearer <token>`
- `Content-Type: application/json`
- 目标 endpoint：`https://api.tavily.com/extract`
- 返回应尽量转换成当前 `WebFetch` 既有输出结构能消费的形态
- 建议在输出里保留额外元信息，例如：
  - `fetch_via = tavily_extract`
  - `origin_status`
  - 必要时保留原始 URL / fallback URL 线索

## 对 session `4748335c558e699352bb27b4ae06ecd7` 的诊断摘要

### 用户满意的部分
- 六部对“战争是否超过三周”的分部论证，本身质量高
- 兵部、工部、户部、礼部等围绕自己的角度做推演，这个方向是对的
- 尚书省和太子最后的综合判断也比之前更像“有判断的官员”

### 用户不满意的点
- 当用户要求“论据、论证过程、具体路径、过程”时，六部整体仍偏重纯逻辑推演
- 事实、数字、公开时间线、公开来源的补强不够
- 有些部即便工具层面做了联网，也没有把证据真正回填到正文里
- `WebFetch` 在 Reuters、Cloudflare、JS 壳场景下经常抓不到正文，导致 evidence gathering 很鸡肋

### 根因（供下一任参考）
当前 prompt gating 倾向于：
- 只有“明确核实/查证/求证/传闻”才触发联网
- 而“论证题需要事实支撑”没有被单独当成一种触发条件

这会导致：
- 六部继续按高质量逻辑推演来写
- 但不会系统性地在关键论据上补事实和数字


### 本轮已经明确的否定项
- **不要**把“论证题 = 整体轻量 research”写死
- **不要**上 reader 兜底
- `WebFetch` 的 fallback 只接受 **Tavily Extract** 方向

## 下一任的最小行动清单

1. 先读本文件，不要再按“整类任务变成 research”理解需求
2. 把 prompt 改成“论据级证据增强”，不是“整篇 research 化”
3. 确认 `Task` / subagent 能否在 workflow step agent 中实际可用
4. 若可用，给六部 prompt 增加“必要时启动 subagent 做小型 deep-research 取证”的口径
5. 若不可用，先允许六部 agent 直接用 `WebSearch/WebFetch` 模拟这个动作，但设计语义仍对齐 subagent 取证
6. 在 `openagentic_tool_webfetch.erl` 中接入 Tavily Extract fallback
7. 只在下一任里做验证：
   - 定向 eunit
   - 全量 eunit
   - 必要时在线试抓 Reuters / Cloudflare 场景

## 一句话交接

> 保留六部当前高质量论证方式，不要整篇 research 化；只在关键论据需要事实、数字、时间线时，给该论据挂一个 subagent / deep-research 式取证动作；`WebFetch` 的反爬兜底只走 Tavily Extract，不走 reader。

## 2026-03-06 实施回写

- 已新增内置 `research` 子代理，并让 runtime 自动按 `task_agents` 装配 built-in runners。
- 已将 `three-provinces-six-ministries.v1` 的六部 step `tool_policy` 放开 `Task`，可直接发起 `Task(agent="research", ...)`。
- 已把 `shangshu_dispatch`、`zhongshu_plan`、六部 prompts 改成“论据级证据增强”语义：保留原有论证骨架，不整篇 research 化，只对关键论据补 1~3 条公开证据。
- 已在 `WebFetch` 接入 Tavily Extract fallback：命中 JS 壳 / Cloudflare / 401/403/429 / 空正文时，优先尝试 Tavily Extract，并在输出中保留 `fetch_via=tavily_extract` 与 `origin_status`。
- 已补齐 eunit 覆盖：`Task/research` 子代理自动装配、workflow prompt/tool-policy、以及 `WebFetch -> Tavily Extract` 回退。
- 验证结果：`rebar3 eunit` 全量通过（`165 tests, 0 failures`）。
