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

- [x] 固化 `src` 大模块统一拆分模板：`facade + sibling subdir`
  - 结果证据：已在 `openagentic_case_store`、`openagentic_workflow_engine`、`openagentic_runtime`、`openagentic_tool_webfetch`、`openagentic_tool_websearch` 等条目统一落成薄 facade + 同名子目录模块。
- [x] 明确 `test` 是否允许递归子目录；如果允许，先在构建配置里补齐约定
  - 结果证据：当前 backlog 执行期仍保持 `apps/openagentic_sdk/test/` 平铺，不启用递归测试子目录；若 Phase 3 真实拆测时需要递归，再先做前置构建约定变更。
- [x] 固化单文件上限：`backlog threshold = 200`，`target ceiling = 150`
  - 结果证据：本文件“仓库级硬约束”与根 `AGENTS.md` 已同步；后续完成条目均按 `> 200` 入 backlog、`<= 150` 作为完成定义。

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
- [x] `1304` 行 `apps/openagentic_sdk/src/openagentic_cli.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_cli/`
  - 实际切口：`main_dispatch`、`main`、`run_chat`、`workflow_web`、`runtime_opts`、`project`、`flags`、`values`、`event_sink`、`tool_use`、`tool_use_search_fs`、`tool_use_content`、`tool_use_tasking`、`tool_result`、`tool_result_web`、`tool_result_fs`、`tool_result_misc`、`tool_output_utils`、`ansi`、`text_format`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_cli.erl` 已收缩为 `28` 行 facade；新增 20 个同名子目录模块，最大文件 `118` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_cli_flags_test --module=openagentic_cli_project_dir_test --module=openagentic_cli_dotenv_precedence_test --module=openagentic_cli_observability_test`
  - 验证结果：`7 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 cli 拆分未引入新失败。
- [x] `719` 行 `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_workflow_dsl/`
  - 实际切口：`api`、`steps`、`transitions`、`step_fields`、`guards`、`retry`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_workflow_dsl.erl` 已收缩为 `11` 行 facade；新增 7 个同名子目录模块，最大文件 `109` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_workflow_dsl_test`
  - 验证结果：`6 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 workflow_dsl 拆分未引入新失败。
- [x] `476` 行 `apps/openagentic_sdk/src/openagentic_case_scheduler.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_case_scheduler/`
  - 实际切口：`state_refresh`、`due_scan`、`dispatch`、`schedule_eval`、`time`、`store`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_case_scheduler.erl` 已收缩为 `33` 行 facade；新增 7 个同名子目录模块，最大文件 `137` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_case_store_test`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 case_scheduler 拆分未引入新失败。
- [x] `460` 行 `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_workflow_mgr/`
  - 实际切口：`calls`、`info`、`tracking`、`stalls`、`status`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_workflow_mgr.erl` 已收缩为 `35` 行 facade；新增 6 个同名子目录模块，最大文件 `63` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_workflow_mgr_test --module=openagentic_web_runtime_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 workflow_mgr 拆分未引入新失败。
- [x] `459` 行 `apps/openagentic_sdk/src/openagentic_compaction.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_compaction/`
  - 实际切口：`prompts`、`overflow`、`prune`、`transcript`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_compaction.erl` 已收缩为 `9` 行 facade；新增 5 个同名子目录模块，最大文件 `100` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_compaction_test`
  - 验证结果：`2 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 compaction 拆分未引入新失败。
- [x] `454` 行 `apps/openagentic_sdk/src/openagentic_events.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_events/`
  - 实际切口：`messages`、`tooling`、`workflow`、`runtime`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_events.erl` 已收缩为 `27` 行 facade；新增 5 个同名子目录模块，最大文件 `41` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_events_schema_test`
  - 验证结果：`2 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `162 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 events 拆分未引入新失败。
- [x] `300` 行 `apps/openagentic_sdk/src/openagentic_provider_retry.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_provider_retry/`
  - 实际切口：`call`、`classify`、`parse`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_provider_retry.erl` 已收缩为 `7` 行 facade；新增 `4` 个同名子目录模块，最大文件 `55` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_provider_retry_test`
  - 验证结果：`4 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `163 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 provider retry 拆分未引入新失败。
- [x] `258` 行 `apps/openagentic_sdk/src/openagentic_task_runners.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_task_runners/`
  - 实际切口：`compose`、`builtin`、`progress`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_task_runners.erl` 已收缩为 `7` 行 facade；新增 `4` 个同名子目录模块，最大文件 `74` 行；补充测试 `apps/openagentic_sdk/test/openagentic_task_runners_test.erl` 共 `22` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_task_runners_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `166 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 task runners 拆分未引入新失败。
- [x] `204` 行 `apps/openagentic_sdk/src/openagentic_session_store.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_session_store/`
  - 实际切口：`append`、`layout`、`read`、`tail_repair`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_session_store.erl` 已收缩为 `8` 行 facade；新增 `5` 个同名子目录模块，最大文件 `41` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_session_store_test --module=openagentic_events_schema_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `166 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 session store 拆分未引入新失败。
- [x] `201` 行 `apps/openagentic_sdk/src/openagentic_time_context.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_time_context/`
  - 实际切口：`resolve`、`render`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_time_context.erl` 已收缩为 `10` 行 facade；新增 `3` 个同名子目录模块，最大文件 `58` 行；补充测试 `compose_system_prompt_does_not_duplicate_marker_test/0`。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_time_context_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `167 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 time context 拆分未引入新失败。

### Phase 2：再拆 Provider / Tool / Infra 表面层

这些模块对外接口多，但切口通常比核心运行时更稳定；适合在主链稳定后连续推进。

- [x] `995` 行 `apps/openagentic_sdk/src/openagentic_tool_webfetch.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_webfetch/`
  - 实际切口：`api`、`request`、`safety`、`sanitize`、`runtime`、`extract`、`anchors`、`tags`、`markdown`、`tavily`、`tavily_format`、`tavily_support`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_webfetch.erl` 已收缩为 `11` 行 facade；新增 `12` 个同名子目录模块，最大文件 `136` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tools_contract_test`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `167 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 WebFetch 拆分未引入新失败。
- [x] `555` 行 `apps/openagentic_sdk/src/openagentic_tool_lsp.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_lsp/`
  - 实际切口：`api`、`actions`、`client`、`protocol`、`config`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_lsp.erl` 已收缩为 `51` 行 facade；新增 `6` 个同名子目录模块，最大文件 `107` 行；补充测试 `apps/openagentic_sdk/test/openagentic_tool_lsp_test.erl`。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tool_lsp_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 tool lsp 拆分未引入新失败。
- [x] `540` 行 `apps/openagentic_sdk/src/openagentic_openai_responses.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_openai_responses/`
  - 实际切口：`api`、`runtime`、`request`、`stream`、`normalize`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_openai_responses.erl` 已收缩为 `11` 行 facade；新增 `6` 个同名子目录模块，最大文件 `139` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_openai_responses_test`
  - 验证结果：`6 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 openai responses 拆分未引入新失败。
- [x] `496` 行 `apps/openagentic_sdk/src/openagentic_tool_websearch.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_websearch/`
  - 实际切口：`api`、`tavily`、`duckduckgo`、`domain`、`text`、`runtime`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_websearch.erl` 已收缩为 `12` 行 facade；新增 7 个同名子目录模块，最大文件 `108` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tools_contract_test`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 websearch 拆分未引入新失败。
- [x] `488` 行 `apps/openagentic_sdk/src/openagentic_tool_grep.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_grep/`
  - 实际切口：`api`、`search`、`scan`、`filters`、`walk`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_grep.erl` 已收缩为 `11` 行 facade；新增 6 个同名子目录模块，最大文件 `105` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test --module=openagentic_tools_contract_test --module=openagentic_tool_schemas_test`
  - 验证结果：`23 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 grep 拆分未引入新失败。
- [x] `422` 行 `apps/openagentic_sdk/src/openagentic_tool_bash.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_bash/`
  - 实际切口：`api`、`exec`、`output`、`path_normalize`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_bash.erl` 已收缩为 `11` 行 facade；新增 5 个同名子目录模块，最大文件 `103` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tools_contract_test`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 bash 拆分未引入新失败。
- [x] `398` 行 `apps/openagentic_sdk/src/openagentic_tool_schemas.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_schemas/`
  - 实际切口：`api`、`descriptions`、`params_dispatch`、`params_fs`、`params_interactive`、`params_web`、`params_misc`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_schemas.erl` 已收缩为 `9` 行 facade；新增 8 个同名子目录模块，最大文件 `77` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tool_schemas_test`
  - 验证结果：`6 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 tool schemas 拆分未引入新失败。
- [x] `386` 行 `apps/openagentic_sdk/src/openagentic_tool_read.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_read/`
  - 实际切口：`api`、`file_read`、`line_window`、`byte_read`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_read.erl` 已收缩为 `11` 行 facade；新增 5 个同名子目录模块，最大文件 `92` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test --module=openagentic_tools_contract_test`
  - 验证结果：`23 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 read 拆分未引入新失败。
- [x] `372` 行 `apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_openai_chat_completions/`
  - 实际切口：`api`、`transform`、`parse`、`runtime`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl` 已收缩为 `21` 行 facade；新增 5 个同名子目录模块，最大文件 `76` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_openai_chat_completions_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 chat completions 拆分未引入新失败。
- [x] `360` 行 `apps/openagentic_sdk/src/openagentic_skills.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_skills/`
  - 实际切口：`api`、`discovery`、`markdown`、`sections`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_skills.erl` 已收缩为 `6` 行 facade；新增 5 个同名子目录模块，最大文件 `82` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_skills_tool_test --module=openagentic_skills_index_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 skills 拆分未引入新失败。
- [x] `325` 行 `apps/openagentic_sdk/src/openagentic_fs.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_fs/`
  - 实际切口：`paths`、`guards`、`symlink`、`normalize`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_fs.erl` 已收缩为 `19` 行 facade；新增 `5` 个同名子目录模块，最大文件 `83` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test`
  - 验证结果：`23 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 fs 拆分未引入新失败。
- [x] `317` 行 `apps/openagentic_sdk/src/openagentic_tool_glob.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_glob/`
  - 实际切口：`api`、`pattern`、`scan`、`render`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_glob.erl` 已收缩为 `12` 行 facade；新增 `5` 个同名子目录模块，最大文件 `107` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test`
  - 验证结果：`23 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tools_contract_test`
  - 扩展结果：`19 tests, 0 failures`
  - 补充验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tool_schemas_test`
  - 补充结果：`6 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 glob 拆分未引入新失败。
- [x] `314` 行 `apps/openagentic_sdk/src/openagentic_permissions.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_permissions/`
  - 实际切口：`gate`、`approve`、`finalize`、`policy`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_permissions.erl` 已收缩为 `45` 行 facade；新增 `5` 个同名子目录模块，最大文件 `96` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_permissions_test`
  - 验证结果：`8 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_permission_mode_override_test`
  - 扩展结果：`3 tests, 0 failures`
  - 补充验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_hitl_order_test`
  - 补充结果：`1 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 permissions 拆分未引入新失败。
- [x] `272` 行 `apps/openagentic_sdk/src/openagentic_tool_edit.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_edit/`
  - 实际切口：`api`、`apply`、`anchors`、`replace`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_edit.erl` 已收缩为 `12` 行 facade；新增 `5` 个同名子目录模块，最大文件 `113` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test`
  - 验证结果：`23 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 tool_edit 拆分未引入新失败。
- [x] `242` 行 `apps/openagentic_sdk/src/openagentic_anthropic_messages.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_anthropic_messages/`
  - 实际切口：`complete`、`request`、`response`、`stream`、`http`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_anthropic_messages.erl` 已收缩为 `8` 行 facade；新增 `6` 个同名子目录模块，最大文件 `67` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_anthropic_parsing_test`
  - 验证结果：`3 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_anthropic_sse_decoder_test`
  - 扩展结果：`1 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 anthropic_messages 拆分未引入新失败。
- [x] `242` 行 `apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder/`
  - 实际切口：`events`、`state`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_anthropic_sse_decoder.erl` 已收缩为 `12` 行 facade；新增 `3` 个同名子目录模块，最大文件 `98` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_anthropic_sse_decoder_test`
  - 验证结果：`1 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_anthropic_parsing_test`
  - 扩展结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 anthropic_sse_decoder 拆分未引入新失败。
- [x] `240` 行 `apps/openagentic_sdk/src/openagentic_tool_notebook_edit.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_notebook_edit/`
  - 实际切口：`api`、`ops`、`cells`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_notebook_edit.erl` 已收缩为 `12` 行 facade；新增 `4` 个同名子目录模块，最大文件 `78` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tools_contract_test`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 tool_notebook_edit 拆分未引入新失败。
- [x] `228` 行 `apps/openagentic_sdk/src/openagentic_anthropic_parsing.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_anthropic_parsing/`
  - 实际切口：`input`、`tools`、`output`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_anthropic_parsing.erl` 已收缩为 `16` 行 facade；新增 `4` 个同名子目录模块，最大文件 `105` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_anthropic_parsing_test`
  - 验证结果：`3 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 anthropic_parsing 拆分未引入新失败。
- [x] `209` 行 `apps/openagentic_sdk/src/openagentic_tool_list.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_tool_list/`
  - 实际切口：`api`、`scan`、`render`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_tool_list.erl` 已收缩为 `12` 行 facade；新增 `4` 个同名子目录模块，最大文件 `48` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_fs_tools_test`
  - 验证结果：`23 tests, 0 failures`
  - 扩展验证：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_tool_schemas_test`
  - 扩展结果：`6 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 tool_list 拆分未引入新失败。

### Phase 3：测试与 E2E 相关文件

测试文件不要求和 `src` 完全一样的目录策略，但必须避免再出现巨型“全能测试文件”。

- [x] `990` 行 `apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl`
  - 实际目标：`apps/openagentic_sdk/test/`
  - 实际切口：`core`、`contracts`、`retry`、`continue`、`decision_route`、`fanout`、`prompts`、`three_provinces_prompts`；共享 support 抽到 `workflows_a`、`workflows_b`、`workflows_c`、`test_utils`
  - 结果证据：`apps/openagentic_sdk/test/openagentic_workflow_engine_test.erl` 已收缩为 `1` 行 stub；新增 `8` 个拆分 `*_test.erl` 模块与 `4` 个 support 模块，最大文件 `138` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; $mods='openagentic_workflow_engine_core_test','openagentic_workflow_engine_contracts_test','openagentic_workflow_engine_retry_test','openagentic_workflow_engine_continue_test','openagentic_workflow_engine_decision_route_test','openagentic_workflow_engine_fanout_test','openagentic_workflow_engine_prompts_test','openagentic_workflow_engine_three_provinces_prompts_test'; foreach($m in $mods){ rebar3 eunit --module=$m }`
  - 验证结果：`27 tests, 0 failures`（`3 + 2 + 2 + 2 + 2 + 3 + 5 + 8`）
  - 全量门禁备注：`rebar3 eunit` 当前仍是 `170 tests, 0 failures, 3 cancelled`；已知取消点仍为 `openagentic_web_case_governance_test:governance_session_query_injects_task_context_test/0` 超时，本轮 workflow_engine 测试拆分未引入新失败。
- [x] `977` 行 `apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl`
  - 实际目标：`apps/openagentic_sdk/test/`
  - 实际切口：`phase1`、`session_query`、`task_detail`、`task_context`、`monitoring`、`task_revision`、`reauth_hint`、`library_inbox`、`case_create`、`static_page`；共享 support 抽到 `openagentic_web_case_governance_test_support.erl`
  - 结果证据：`apps/openagentic_sdk/test/openagentic_web_case_governance_test.erl` 已收缩为 `1` 行 stub；新增 `10` 个拆分 `*_test.erl` 模块与 `1` 个 support 模块，最大文件 `147` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; $mods='openagentic_web_case_governance_phase1_test','openagentic_web_case_governance_session_query_test','openagentic_web_case_governance_task_detail_test','openagentic_web_case_governance_monitoring_test','openagentic_web_case_governance_task_revision_test','openagentic_web_case_governance_reauth_hint_test','openagentic_web_case_governance_library_inbox_test','openagentic_web_case_governance_case_create_test','openagentic_web_case_governance_static_page_test'; foreach($m in $mods){ rebar3 eunit --module=$m }`
  - 验证结果：`9 tests, 0 failures`
  - 已知定向备注：`rebar3 eunit --module=openagentic_web_case_governance_task_context_test` 当前仍是 `2 tests, 0 failures, 2 cancelled`，对应既有 timeout 场景 `governance_session_query_injects_task_context_test/0`
  - 全量门禁备注：`rebar3 eunit` 当前为 `173 tests, 0 failures, 2 cancelled`；已知取消点为 `openagentic_web_case_governance_task_context_test:governance_session_query_injects_task_context_test/0` 超时，本轮 governance 测试拆分未引入新失败。
- [x] `898` 行 `apps/openagentic_sdk/test/openagentic_case_store_test.erl`
  - 实际目标：`apps/openagentic_sdk/test/`
  - 实际切口：`case_create`、`approve`、`task_revision`、`task_reauth`、`credential_binding`、`monitoring_run`、`run_retry`、`run_delivery`、`template_library`、`inbox`；共享 support 抽到 `openagentic_case_store_test_support.erl`
  - 结果证据：`apps/openagentic_sdk/test/openagentic_case_store_test.erl` 已收缩为 `1` 行 stub；新增 `10` 个拆分 `*_test.erl` 模块与 `1` 个 support 模块，最大文件 `137` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; $mods='openagentic_case_store_case_create_test','openagentic_case_store_approve_test','openagentic_case_store_task_revision_test','openagentic_case_store_task_reauth_test','openagentic_case_store_credential_binding_test','openagentic_case_store_monitoring_run_test','openagentic_case_store_run_retry_test','openagentic_case_store_run_delivery_test','openagentic_case_store_template_library_test','openagentic_case_store_inbox_test'; foreach($m in $mods){ rebar3 eunit --module=$m }`
  - 验证结果：`19 tests, 0 failures`
  - 全量门禁备注：`rebar3 eunit` 当前为 `173 tests, 0 failures, 2 cancelled`；已知取消点为 `openagentic_web_case_governance_task_context_test:governance_session_query_injects_task_context_test/0` 超时，本轮 case_store 测试拆分未引入新失败。
- [x] `756` 行 `apps/openagentic_sdk/src/openagentic_e2e_online.erl`
  - 实际目标：`apps/openagentic_sdk/src/openagentic_e2e_online/`
  - 实际切口：`runner`、`cases_basic`、`cases_tools`、`cases_webfetch`、`query`、`assert`、`fixtures`、`utils`
  - 结果证据：`apps/openagentic_sdk/src/openagentic_e2e_online.erl` 已收缩为 `20` 行 facade；新增 `8` 个子模块，最大文件 `131` 行。
  - 验证命令：`. .\scripts\erlang-env.ps1 -SkipRebar3Verify; rebar3 eunit --module=openagentic_e2e_online_test`
  - 验证结果：`0 tests`（`OPENAGENTIC_E2E` 未开启，完成编译与模块装载）
  - 全量门禁备注：`rebar3 eunit` 当前为 `173 tests, 0 failures, 2 cancelled`；已知取消点为 `openagentic_web_case_governance_task_context_test:governance_session_query_injects_task_context_test/0` 超时，本轮 e2e_online 源码拆分未引入新失败。
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
- 执行本 backlog 时，所有 shell 命令都必须显式使用 `pwsh.exe`；禁止回退到 `powershell.exe` 5.x
- 读取、回写、检查仓库文本文件时，只允许 `pwsh.exe` 或 Python 显式 UTF-8 API
- 每拆完一个条目，都要留下“切口说明 + 验证命令 + 结果证据”
- 如果某个条目需要先改构建约定（尤其是 `test` 目录递归编译），先把它升级为前置条目，不要硬拆
- 对于已有样板，优先复用已经形成的模式，不要每个条目发明一套新结构

---

## 当前基线统计

- `src` 目标文件：`32`
- `test` 目标文件：`7`
- 合计：`39`

建议按 `Phase 0 -> Phase 1 -> Phase 2 -> Phase 3` 顺序推进，不要跳着拆。
