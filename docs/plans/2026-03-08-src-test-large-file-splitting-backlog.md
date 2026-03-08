# Src/Test 大文件拆分 Backlog

> **For Codex:** REQUIRED SUB-SKILL: 实施任一条目时，必须先用 `superpowers:spaghetti-refactor`；如果要按条目连续执行，再配合 `superpowers:executing-plans`。

**Goal:** 逐步清除 `apps/openagentic_sdk/src/` 与 `apps/openagentic_sdk/test/` 中所有超过 200 行的文件，并把拆分后的结果文件统一压到 150 行以内。

**Baseline:** 本文基于 `2026-03-08` 当天对 `HEAD` 的受 Git 管理文本文件扫描，仅统计 `src/` 与 `test/`；不再扫描 `docs/`、`priv/web/`、`README`、`skills/`、`workflows/` 等非本次可重构范围。

**Current Counts:** 共 `39` 个目标文件，其中 `src = 32`，`test = 7`。

---

## 仓库级硬约束

这些约束来自本轮 `openagentic_case_store` 拆分要求，后续 backlog 条目统一遵守：

1. **入 backlog 阈值**：凡是 `src/` 或 `test/` 下单文件 `> 200` 行，必须进入 backlog。
2. **拆分后硬上限**：任何新生成或重写后的目标文件，单文件都必须 `<= 150` 行。
3. **源码落位规则**：`src` 下的大模块，优先改成“薄 facade + 同名子目录实现模块”的结构；不要把新模块平铺得到处都是。
   - 参考样板：`apps/openagentic_sdk/src/openagentic_case_store.erl`
   - 参考子目录：`apps/openagentic_sdk/src/openagentic_case_store/`
4. **测试落位规则**：`test` 下的大测试文件，优先按场景拆成多个 `*_test.erl`；若确实需要测试子目录，必须先确认/补齐测试递归编译约定。
5. **行为稳定优先**：重构必须保持外部 API、事件格式、测试语义不变；先拆职责，再做命名清理，不允许顺手改需求。
6. **验证顺序**：先跑最小相关测试，再跑 `rebar3 eunit`；若全量门禁有已知非本次问题，必须在条目证据里单独注明。
7. **禁止打散根目录**：一个大文件拆成多个模块时，必须有清晰的家目录，例如：
   - `apps/openagentic_sdk/src/openagentic_runtime.erl`
   - `apps/openagentic_sdk/src/openagentic_runtime/`
8. **完成定义（DoD）**：每个条目只有在以下条件同时满足时才算完成：
   - 原始大文件已拆散，或收缩为不超过 150 行的 facade
   - 新文件全部不超过 150 行
   - 新模块放入约定子目录或同组测试集合
   - 相关测试通过，并记录验证命令

---

## 建议执行顺序

### Phase 0：先固化约定

- [ ] 固化 `src` 大模块统一拆分模板：`facade + sibling subdir`
- [ ] 明确 `test` 是否允许递归子目录；如果允许，先在构建配置里补齐约定
- [ ] 固化单文件上限：`backlog threshold = 200`，`target ceiling = 150`

### Phase 1：先拆核心运行时与工作流主链

优先处理最深、最耦合、最容易阻塞后续功能演进的核心源文件。

- [x] `1576` 行 `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_workflow_engine/`
  - 实际切口：`run`、`continue`、`history_time`、`history_steps`、`execution`、`fanout_wait`、`fanout_child`、`retry`、`executor`、`tooling`、`prompts`、`contracts`、`output_helpers`、`state`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_workflow_engine.erl` 已收缩为 `16` 行 facade；新增 15 个同名子目录模块，最大文件 `140` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_workflow_engine_test`
  - 验证结果：`27 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_workflow_engine_test --module=openagentic_workflow_mgr_test`
  - 扩展结果：`27 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前在 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 出现既有超时取消（`162 tests, 0 failures, 3 cancelled`）；本轮变更相关的 workflow 护栏已全部通过。
- [x] `1498` 行 `apps/openagentic_sdk/src/openagentic_runtime.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_runtime/`
  - 实际切口：`query`、`query_setup`、`query_state`、`resume`、`loop`、`model`、`compaction`、`tools`、`events`、`artifacts`、`truncate_hint`、`truncate_headtail`、`finalize`、`options`、`paths`、`tasks`、`questions`、`permissions`、`errors`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_runtime.erl` 已收缩为 `5` 行 facade；新增 20 个同名子目录模块，最大文件 `137` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tool_loop_test --module=openagentic_runtime_resume_test --module=openagentic_runtime_api_key_header_test --module=openagentic_runtime_openai_store_test --module=openagentic_runtime_provider_error_semantics_test --module=openagentic_hitl_order_test --module=openagentic_partial_messages_test --module=openagentic_permission_mode_override_test`
  - 验证结果：`5 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 runtime 拆分未引入新失败。
- [ ] `1304` 行 `apps/openagentic_sdk/src/openagentic_cli.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_cli/`
  - 建议切口：`main`、`arg_parse`、`chat_cmd`、`workflow_cmd`、`web_cmd`、`formatter`
- [ ] `719` 行 `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_workflow_dsl/`
  - 建议切口：`loader`、`validator`、`normalizer`、`guard_schema`、`defaults`
- [ ] `476` 行 `apps/openagentic_sdk/src/openagentic_case_scheduler.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_case_scheduler/`
  - 建议切口：`due_scan`、`schedule_eval`、`dispatch`、`state_refresh`
- [ ] `460` 行 `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_workflow_mgr/`
  - 建议切口：`queue_ops`、`continue_cancel`、`stall_resume`、`status_queries`
- [ ] `459` 行 `apps/openagentic_sdk/src/openagentic_compaction.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_compaction/`
  - 建议切口：`policy`、`collector`、`rewrite`、`stats`
- [ ] `454` 行 `apps/openagentic_sdk/src/openagentic_events.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_events/`
  - 建议切口：`workflow_events`、`runtime_events`、`web_events`、`helpers`
- [ ] `300` 行 `apps/openagentic_sdk/src/openagentic_provider_retry.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_provider_retry/`
  - 建议切口：`policy`、`backoff`、`classify`、`wrapper`
- [ ] `258` 行 `apps/openagentic_sdk/src/openagentic_task_runners.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_task_runners/`
  - 建议切口：`registry`、`dispatch`、`builtin_runners`、`errors`
- [ ] `204` 行 `apps/openagentic_sdk/src/openagentic_session_store.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_session_store/`
  - 建议切口：`layout`、`append`、`read`、`tail_repair`
- [ ] `201` 行 `apps/openagentic_sdk/src/openagentic_time_context.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_time_context/`
  - 建议切口：`clock`、`timezone`、`injection`、`format`

### Phase 2：再拆 Provider / Tool / Infra 表面层

这些模块对外接口多，但切口通常比核心运行时更稳定；适合在主链稳定后连续推进。

- [ ] `995` 行 `apps/openagentic_sdk/src/openagentic_tool_webfetch.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_webfetch/`
  - 建议切口：`facade`、`safety`、`request`、`extract`、`bounded_output`
- [ ] `555` 行 `apps/openagentic_sdk/src/openagentic_tool_lsp.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_lsp/`
  - 建议切口：`protocol`、`transport`、`actions`、`normalize`
- [ ] `540` 行 `apps/openagentic_sdk/src/openagentic_openai_responses.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_openai_responses/`
  - 建议切口：`request`、`stream_parse`、`tool_call_bridge`、`normalize`
- [ ] `496` 行 `apps/openagentic_sdk/src/openagentic_tool_websearch.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_websearch/`
  - 建议切口：`tavily`、`duckduckgo`、`normalize`、`render`
- [ ] `488` 行 `apps/openagentic_sdk/src/openagentic_tool_grep.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_grep/`
  - 建议切口：`matcher`、`context_window`、`limits`、`render`
- [ ] `422` 行 `apps/openagentic_sdk/src/openagentic_tool_bash.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_bash/`
  - 建议切口：`command_parse`、`policy`、`execution`、`render`
- [ ] `398` 行 `apps/openagentic_sdk/src/openagentic_tool_schemas.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_schemas/`
  - 建议切口：`schema_build`、`json_types`、`merge`、`render`
- [ ] `386` 行 `apps/openagentic_sdk/src/openagentic_tool_read.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_read/`
  - 建议切口：`safety`、`range`、`binary_text`、`render`
- [ ] `372` 行 `apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_openai_chat_completions/`
  - 建议切口：`request`、`stream_parse`、`tool_call_bridge`、`normalize`
- [ ] `360` 行 `apps/openagentic_sdk/src/openagentic_skills.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_skills/`
  - 建议切口：`discovery`、`precedence`、`front_matter`、`summary`
- [ ] `325` 行 `apps/openagentic_sdk/src/openagentic_fs.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_fs/`
  - 建议切口：`path_ops`、`sandbox`、`file_ops`、`copy_move`
- [ ] `317` 行 `apps/openagentic_sdk/src/openagentic_tool_glob.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_glob/`
  - 建议切口：`pattern`、`walk`、`limits`、`render`
- [ ] `314` 行 `apps/openagentic_sdk/src/openagentic_permissions.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_permissions/`
  - 建议切口：`policy`、`defaults`、`workspace_scope`、`classify`
- [ ] `272` 行 `apps/openagentic_sdk/src/openagentic_tool_edit.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_edit/`
  - 建议切口：`patch_parse`、`apply`、`validate`、`render`
- [ ] `242` 行 `apps/openagentic_sdk/src/openagentic_anthropic_messages.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_anthropic_messages/`
  - 建议切口：`request`、`content_blocks`、`tooling`、`normalize`
- [ ] `242` 行 `apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder/`
  - 建议切口：`frame_decode`、`event_decode`、`state`、`helpers`
- [ ] `240` 行 `apps/openagentic_sdk/src/openagentic_tool_notebook_edit.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_notebook_edit/`
  - 建议切口：`notebook_io`、`cell_ops`、`validation`、`render`
- [ ] `228` 行 `apps/openagentic_sdk/src/openagentic_anthropic_parsing.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_anthropic_parsing/`
  - 建议切口：`delta_parse`、`tool_use_parse`、`finish_reason`、`normalize`
- [ ] `209` 行 `apps/openagentic_sdk/src/openagentic_tool_list.erl`
  - 建议目标：`apps/openagentic_sdk/src/openagentic_tool_list/`
  - 建议切口：`list_dir`、`filters`、`metadata`、`render`

### Phase 3：测试与 E2E 相关文件

测试文件不要求和 `src` 完全一样的目录策略，但必须避免再出现巨型“全能测试文件”。

- [ ] `990` 行 `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl`
  - 建议切口：`dsl`、`guards`、`fanout_join`、`retry`、`queue_cancel`
- [ ] `977` 行 `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`
  - 建议切口：`cases`、`candidates`、`tasks`、`governance_query`、`inbox`
- [ ] `898` 行 `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
  - 建议切口：`case_create`、`candidate_flow`、`template_flow`、`task_flow`、`run_flow`、`fixtures`
- [ ] `756` 行 `apps/openagentic_sdk/src/openagentic_e2e_online.erl`
  - 这是测试邻近源码，建议和测试一起处理
  - 建议目标：`apps/openagentic_sdk/src/openagentic_e2e_online/`
  - 建议切口：`bootstrap`、`provider_cases`、`workflow_cases`、`web_cases`、`assertions`
- [ ] `412` 行 `apps/openagentic_sdk/test/openagentic_fs_tools_test.erl`
  - 建议切口：`read_write`、`edit`、`glob_grep`、`safety`
- [ ] `285` 行 `apps/openagentic_sdk/test/openagentic_web_runtime_test.erl`
  - 建议切口：`health`、`sse`、`workspace_read`、`question_answer`
- [ ] `265` 行 `apps/openagentic_sdk/test/openagentic_tools_contract_test.erl`
  - 建议切口：`registry`、`schemas`、`tool_contract`
- [ ] `261` 行 `apps/openagentic_sdk/test/openagentic_web_e2e_online_test.erl`
  - 建议切口：`startup_smoke`、`query_smoke`、`workflow_smoke`、`governance_smoke`

---

## 推荐执行纪律

- 每次只开一个 backlog 条目，不要并行拆多个高耦合核心文件
- 每拆完一个 backlog 条目，必须先 `git add` + `git commit` + `git push`，再继续下一条；提交中要同时带上对应 backlog 证据更新
- 每拆完一个条目，都要留下“切口说明 + 验证命令 + 结果证据”
- 如果某个条目需要先改构建约定（尤其是 `test` 目录递归编译），先把它升级为前置条目，不要硬拆
- 对于已有样板，优先复用已经形成的模式，不要每个条目发明一套新结构

---

## 当前基线统计

- `src` 目标文件：`32`
- `test` 目标文件：`7`
- 合计：`39`

建议按 `Phase 0 -> Phase 1 -> Phase 2 -> Phase 3` 顺序推进，不要跳着拆。
