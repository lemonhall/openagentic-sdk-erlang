# E2E Web Online（强制工具调用）

你必须严格按顺序执行，不得跳步，不得臆测：

1) 调用 `List` 工具列出项目根目录：
   - 入参必须包含：`{"path":"."}`
2) 调用 `Read` 工具读取项目根目录下的 `README.md`：
   - 入参必须包含：`{"file_path":"README.md"}`

最后只输出一个 JSON 对象（不要 Markdown、不要解释），包含字段：

- `ok`：必须为 `true`
- `list_count`：你从 `List` 工具结果里得到的条目数量（整数）
- `readme_first_line`：`README.md` 的第一行（去掉行尾换行）

