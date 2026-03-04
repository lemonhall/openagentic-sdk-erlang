# 2026-03-03 SlashCommand/Skill 对齐设计

## 目标

对齐 `openagentic-sdk-kotlin` 的技能与命令加载语义，使 Erlang 版在 tool-loop 中具备一致的“本地指令/模板”能力：

- `SlashCommand`：按 opencode 兼容规则加载并渲染命令模板。
- `Skill`：按统一规则解析 `SKILL.md` 的 front-matter、summary、checklist，并输出可直接给模型阅读的内容块。

## SlashCommand（模板加载 + 渲染）

### 输入

- `name`（必填）：命令名（不含扩展名），例如 `hello`。
- `args` / `arguments`（可选）：渲染变量 `args`。
- `project_dir`（可选）：相对 `ctx.project_dir` 的子目录（路径安全：拒绝绝对/盘符/`..`）。

### 查找顺序（优先级从高到低）

1. `${project_dir}/.opencode/commands/<name>.md`
2. `${project_dir}/.claude/commands/<name>.md`
3. `${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/commands/<name>.md`

### 渲染

对模板内容做全局替换：

- `${args}` / `{{args}}`
- `${path}` / `{{path}}`（`path` 为向上找到的 worktree 根：含 `.git` 的目录）

输出字段：`name`、`path`、`content`。

## Skill（解析 + 输出字段）

### 解析规则

- 支持 YAML-ish front matter（`---`…`---`）中的 `name` / `description`。
- title：front matter 未提供 `name` 时，使用正文第一个 `# ` 标题；再无则回退到父目录名。
- `summary`：标题后第一段（跳过空行，直到空行或下一段标题）。
- `checklist`：`## Checklist`（大小写不敏感）下的 `-` / `*` 列表项，直到下一个标题。

### 输出

`Skill` 工具输出补充字段：

- `summary`、`checklist`
- `output`：`## Skill: <name>` + `Base directory` + 去 front-matter 的正文
- `metadata`：`name`、`dir`

## 测试门禁

新增/改写 eunit 覆盖：

- `SlashCommand` 加载 `.claude/commands` 并正确渲染 `${args}`/`${path}`。
- `Skill` 解析 summary/checklist 并生成 `output`。

