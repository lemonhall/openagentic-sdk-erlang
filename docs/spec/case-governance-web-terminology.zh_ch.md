# 案卷治理前端词汇表

本词汇表用于约束 Phase 1 Web UI 的用户可见命名，避免同一对象出现多套叫法。

## 词汇表

| 内部概念 | 前端标准叫法 | 说明 |
| --- | --- | --- |
| `case` | 案卷 | 用户在 Cases 域中处理的长期对象。 |
| `case_id` | 案卷 ID | 用户可见字段统一写作 "案卷 ID"，不再写 "Case ID"。 |
| `round_id` | 轮次 ID | 用户可见字段统一写作 "轮次 ID"。 |
| `candidate` | 候选任务 | 尚未转正的候选监测任务。 |
| candidate review session | 审议 / 审议会话 | 只用于候选任务阶段。 |
| approved / active task | 正式任务 | 已转正并进入长期治理的任务。 |
| governance session | 治理会话 | 正式任务阶段的持续对话页。 |
| `mail` item | 案卷消息 | 单条消息对象的用户可见叫法，不再写 "内邮"。 |
| inbox | 统一信箱 | 聚合各案卷消息的页面入口。 |

## 约束

- 一级导航继续保留 `Workflow` / `Cases` / `Inbox`，作为产品域名称。
- 中文页面中，`Cases` 域内的对象统一称为 "案卷"。
- “审议”只用于候选任务阶段；正式任务阶段统一称 "治理会话"。
- `mail`、`case_id`、`governance_session_id` 等 API 字段保持不变，但不直接暴露为中文产品文案。
