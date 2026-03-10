# openagentic-sdk-erlang

中文说明见：[`README.zh_ch.md`](README.zh_ch.md)

`openagentic-sdk-erlang` is an Erlang/OTP sibling of `openagentic-sdk-kotlin`.
Today it already works as a local-first agent runtime, workflow control plane, and lightweight web UI for BEAM-based experimentation.

## Current implementation status

As of **March 7, 2026**, this repository already includes these working pieces:

- **Runtime facade** via `openagentic_sdk:query/2` and `openagentic_runtime:query/2`
- **OpenAI Responses** as the default HTTP provider with SSE streaming
- **Protocol override** for OpenAI Chat Completions legacy mode via `--protocol responses|legacy`
- **Local-first session persistence** with `meta.json` + append-only `events.jsonl`
- **Resume support** through `resume_session_id` and Responses `previous_response_id`
- **Unified time context injection** (`Asia/Shanghai` by default) into system prompts and session metadata
- **Permission gate (HITL)** with safe read-only tools auto-approved in `default` mode
- **Built-in tools**: `AskUserQuestion`, `Read`, `List`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, `WebFetch`, `WebSearch`, `Skill`, `SlashCommand`, `NotebookEdit`, `LSP`, `TodoWrite`, `Task`
- **Skills system** with precedence-aware `SKILL.md` discovery and parsed metadata (`summary`, `checklist`, front matter)
- **Slash commands** compatible with `.opencode/commands` and `.claude/commands` templates
- **Subagent task tool** with built-in `explore` and `research` agents
- **Workflow engine** driven by JSON DSL, including guards, output contracts, per-step tool policies, fanout/join, retry policy, and resumable step sessions
- **Workflow manager** with queued continue, cancel, watchdog stall detection, and `resumed_from_stalled` status
- **Web UI / local control plane** with workflow start/continue/cancel APIs, question answering, workspace read, session chat continuation, health check, and SSE event streaming
- **Hooks and tool output artifacts** (`hook.event`, `HookBlocked`, overflow-to-artifact wrapper)
- **WebFetch safety rules**: blocks localhost/private-style targets and normalizes output as markdown / text / clean HTML
- **WebSearch backends**: Tavily when configured, DuckDuckGo HTML fallback otherwise
- **Offline test coverage** across runtime, providers, sessions, CLI, workflows, tools, skills, web runtime, and time context

Fresh local verification from this workspace:

- `rebar3 eunit` -> **185 tests, 0 failures** on **March 7, 2026**

## Repo layout

```text
apps/openagentic_sdk/
  src/
    openagentic_sdk.erl               public SDK facade
    openagentic_runtime.erl           tool-loop runtime
    openagentic_cli.erl               CLI entry
    openagentic_workflow_dsl.erl      JSON DSL loader/validator
    openagentic_workflow_engine.erl   workflow execution engine
    openagentic_workflow_mgr.erl      queue/cancel/stall manager
    openagentic_web*.erl              local web server + APIs + SSE
    openagentic_tool_*.erl            built-in tools
    openagentic_skills.erl            SKILL.md discovery/indexing
  test/
    *_test.erl                        eunit suites
  priv/
    toolprompts/                      tool description templates
    web/                              static web UI
workflows/
  three-provinces-six-ministries.v1.json
  prompts/
scripts/
  erlang-env.ps1
  e2e-online-suite.ps1
  e2e-web-online.ps1
  kotlin-parity-check.ps1
docs/
  spec/                               workflow DSL + agent-host protocol
  design/ analysis/ plans/            design notes and implementation plans
```

## Architecture overview

### Main entry points

- SDK facade: `apps/openagentic_sdk/src/openagentic_sdk.erl`
- Runtime/tool loop: `apps/openagentic_sdk/src/openagentic_runtime.erl`
- CLI: `apps/openagentic_sdk/src/openagentic_cli.erl`
- Workflow DSL validator: `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
- Workflow engine: `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
- Workflow manager/watchdog: `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
- Web server: `apps/openagentic_sdk/src/openagentic_web.erl`
- Skills indexer: `apps/openagentic_sdk/src/openagentic_skills.erl`
- Tool registry and schemas: `apps/openagentic_sdk/src/openagentic_tool_registry.erl`, `apps/openagentic_sdk/src/openagentic_tool_schemas.erl`

### Data flow

```text
CLI / Web UI / Workflow API
        -> runtime or workflow engine
        -> provider request + SSE/model output parsing
        -> permission gate
        -> tool registry -> tool modules
        -> events appended to session store
        -> web SSE / CLI formatter / workspace readers
```

### Persistence

Default local-first paths:

- Session root: `OPENAGENTIC_SDK_HOME\sessions\<session_id>\`
- Session files:
  - `meta.json`
  - `events.jsonl`
- Skill roots (discovery precedence is more local wins):
  - `OPENAGENTIC_AGENTS_HOME` (default: `%USERPROFILE%\.agents`)
  - `OPENAGENTIC_SDK_HOME` (default: `%USERPROFILE%\.openagentic-sdk`)
  - project root
  - `project/.claude`
- Slash command templates:
  - `project/.opencode/commands/*.md`
  - `project/.claude/commands/*.md`
  - `%USERPROFILE%\.config\opencode\commands\*.md`

## Requirements

- Erlang/OTP 28
- `rebar3`
- Windows PowerShell 7.x recommended
- Network proxy is often needed in mainland setups (`127.0.0.1:7897` is the local default in this repo)

## Quick start (Windows PowerShell)

### 1) Prepare Erlang env + caches on `E:`

```powershell
# With proxy
. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify

# Without proxy
# . .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

This script sets:

- `ERLANG_HOME=E:\lang\erlang`
- `REBAR_BASE_DIR=E:\erlang\rebar3`
- `REBAR_CACHE_DIR=E:\erlang\rebar3\cache`
- `HEX_HOME=E:\erlang\hex`

### 2) Run offline tests

```powershell
rebar3 eunit
```

### 3) Start an Erlang shell

```powershell
rebar3 shell
```

Inside the shell:

```erlang
%% one-shot query
openagentic_cli:main(["run", "Hello from Erlang!"]).

%% interactive chat
openagentic_cli:main(["chat"]).

%% workflow run (JSON DSL)
openagentic_cli:main([
  "workflow",
  "--dsl", "workflows/three-provinces-six-ministries.v1.json",
  "Plan and implement X"
]).

%% local web UI / control plane
openagentic_cli:main(["web"]).
```

Default Web URL: `http://127.0.0.1:8088/`

## CLI surface

`openagentic_cli:main/1` currently exposes four commands:

- `run` -> single prompt / single session
- `chat` -> interactive shell chat with session resume
- `workflow` -> JSON-DSL workflow execution
- `web` -> local Cowboy-based web UI + APIs

High-value flags:

- `--model <name>`
- `--base-url <url>`
- `--api-key <key>`
- `--protocol <responses|legacy>`
- `--max-steps <1..200>`
- `--stream` / `--no-stream`
- `--permission <bypass|deny|prompt|default>`
- `--project-dir <path>`
- `--session-root <path>`
- `--resume-session-id <sid>`
- `--dsl <path>` for `workflow`
- `--web-bind <ip>` / `--web-port <port>` for `web`
- `--render-markdown` / `--no-render-markdown`
- `--color` / `--no-color`

## Workflow engine (what is already there)

The workflow subsystem is no longer just a stub. Current code supports:

- JSON DSL loading and validation
- step roles + prompt files
- output contracts (`decision`, `markdown_sections`, `json_object`, ...)
- guard checks
- per-step tool policy allow/deny
- step sessions and workflow session event bridging
- fanout/join execution for multi-ministry steps
- retry policy for transient provider failures
- queueing `continue` messages while a workflow is still running
- cancellation and status inspection
- watchdog-based stall detection with persisted `stalled` terminal status

Default demo DSL:

- `workflows/three-provinces-six-ministries.v1.json`

## Web UI / APIs

Current local web server routes:

- `GET /` -> static web UI
- `POST /api/cases` -> create a `case` + origin `deliberation_round` from a completed workflow session
- `GET /api/cases/:case_id/overview` -> load one case with rounds, candidates, tasks, and internal mail
- `POST /api/cases/:case_id/candidates/extract` -> extract `monitoring_candidate` items from the origin round transcript
- `POST /api/cases/:case_id/candidates/:candidate_id/approve` -> promote a candidate into `monitoring_task` + first `task_version`
- `POST /api/cases/:case_id/candidates/:candidate_id/discard` -> discard a candidate in review
- `GET /api/cases/:case_id/templates` -> list case-local `task_template` objects
- `POST /api/cases/:case_id/templates` -> create one case-local `task_template` + template workspace
- `POST /api/cases/:case_id/templates/:template_id/instantiate` -> instantiate a template into a new review candidate
- `GET /api/cases/:case_id/tasks/:task_id/detail` -> load one task with versions, authorization state, credential bindings, run history, and promoted artifacts
- `POST /api/cases/:case_id/tasks/:task_id/run` -> execute one new `monitoring_run` for the task and persist its first `run_attempt`
- `POST /api/cases/:case_id/tasks/:task_id/revise` -> create a new `task_version` on the same `governance_session_id`, supersede the old active version, and keep governance on one long-lived line
- `POST /api/cases/:case_id/tasks/:task_id/credential-bindings` -> upsert one task-level `credential_binding`
- `POST /api/cases/:case_id/tasks/:task_id/activate` -> activate a task after required bindings are satisfied
- `POST /api/cases/:case_id/tasks/:task_id/runs/:run_id/retry` -> append a new `run_attempt` to an existing failed `monitoring_run`
- `POST /api/cases/:case_id/observation-packs` -> create one `observation_pack` that groups task outputs into a reconsideration trigger unit
- `POST /api/cases/:case_id/observation-packs/:pack_id/inspect` -> materialize one `inspection_review` snapshot for the pack; accepts optional `current_revision` and returns `revision_conflict` on stale writes
- `POST /api/cases/:case_id/observation-packs/:pack_id/reconsideration-packages` -> freeze one versioned `reconsideration_package` plus ready-mail notification
- `GET /api/cases/:case_id/reconsideration-packages/:package_id/preview` -> load the frozen reconsideration preview payload, including baseline facts, change facts, controversies, and lifecycle hints
- `POST /api/cases/:case_id/reconsideration-packages/:package_id/defer` -> mark the package as `deferred` and continue observing
- `POST /api/cases/:case_id/reconsideration-packages/:package_id/start` -> revalidate stale/superseded gates, allocate a new `deliberation_round` + `workflow_session_id`, inject `reconsideration_context`, and mark the package as consumed
- `GET /api/inbox` -> query the unified cross-case inbox with status filtering
- `GET /api/inbox/unread-count` -> get unified unread inbox count
- `POST /api/cases/:case_id/mail/:mail_id/read` -> mark inbox items as read
- `POST /api/cases/:case_id/mail/:mail_id/archive` -> archive inbox items
- `POST /api/workflows/start`
- `POST /api/workflows/continue`
- `POST /api/workflows/cancel`
- `POST /api/workspace/read`
- `POST /api/questions/answer`
- `POST /api/sessions/:sid/query` -> continue an existing governance/runtime session in place; when the JSON body includes `case_id` + `task_id`, the server injects `TASK_GOVERNANCE_CONTEXT_V1` from persisted task detail
- `GET /api/sessions/:sid/events` -> SSE session tailing
- `GET /api/health`

The web UI is intentionally local-first and reads from session files rather than a separate database.

Phase 1 case governance metadata is persisted under `cases/<case_id>/...`, while transcripts continue to live under `sessions/<session_id>/...`.

The case governance view now exposes a chat-style governance entry for both `review_session_id` and `governance_session_id` via `view/governance-session.html`, so candidate review can continue on the same long-lived session after promotion. For formal tasks, the same governance view can also create a new `task_version` in place, keeping version revision on the same governance line instead of forcing a parallel flow.

Case governance also now includes `view/task-detail.html`, which surfaces task definition, version history, latest revision diff, reauthorization hints when a revision introduces new credential requirements, authorization status, persisted run history, `run_attempts`, `fact_reports`, execution-session drill-down links, and promoted artifact lists. The same task surface is backed by manual run/retry APIs plus governance-context continuation for Phase 2 monitoring execution.

Active tasks with `schedule_policy` are now scanned by `openagentic_case_scheduler`, so scheduled runs can materialize into persisted `monitoring_run` objects automatically. Run finalization now distinguishes `report_submitted` vs `needs_followup`, and contract/runtime failures emit `exception_brief` plus failure mail for governance follow-up.

Phase 1 now also includes a case-local template library plus a unified inbox view. Templates live under `cases/<case_id>/meta/templates/...` and can be instantiated into fresh candidates without sharing a live task body; inbox data is aggregated from `meta/mail/` into `view/inbox.html` with read/archive/filter actions and corresponding JSON APIs.

Phase 3 adds the inspection and reconsideration loop on top of those monitoring artifacts. `observation_pack`, `inspection_review`, and `reconsideration_package` objects now persist under the case tree, the overview API exposes them alongside tasks/mail, and the preview payload now freezes `based_on_round`, `baseline_facts`, `change_facts`, and controversy text for preview-first review. Review-to-package adoption backlinks are written back through `inspection_review.links.derived_briefing_id`, inspection now records `pending -> reviewing -> ready_for_reconsideration | insufficient` process history, versioned reconsideration packages now carry pack-local `version_no` plus semantic `display_code`, urgent briefs append `urgent_brief_triggered` entries into the case timeline, deferred packages are revalidated against stale/superseded conditions before restart, and new reconsideration rounds start with `reconsideration_context` already injected into the new workflow session instead of relying on ad-hoc prompt reconstruction.

## Tools and safety behavior

### Permission defaults

In `default` mode, these tools are treated as safe when their schema is valid:

- `List`
- `Read`
- `Glob`
- `Grep`
- `WebFetch`
- `WebSearch`
- `Skill`
- `SlashCommand`
- `AskUserQuestion`

Workspace-scoped `Write` / `Edit` operations can also auto-pass when the path resolves inside the configured workspace. Everything else falls back to prompt behavior.

### Notable tool behavior

- `Read` supports offset + line-number-oriented pagination
- `List` helps discovery before `Read` / `Grep`
- `Glob` and `Grep` support recursive matching and stable result ordering
- `WebFetch` can return `markdown`, `text`, or `clean_html`
- `WebSearch` uses Tavily if configured, otherwise falls back to DuckDuckGo HTML parsing
- `Skill` returns parsed metadata plus body content from `SKILL.md`
- `SlashCommand` loads command templates from project/local/global roots
- `Task` can spawn built-in `explore` and `research` subagents
- large tool outputs can be externalized to artifact files with a truncated wrapper
- hooks can emit `hook.event` entries and block tool execution with `HookBlocked`

## Configuration (.env)

The CLI loads `.env` from the resolved project directory.
Never commit real keys.

Minimal example:

```dotenv
OPENAI_API_KEY=your_key_here
MODEL=gpt-4.1-mini
```

Common variables:

- `OPENAI_API_KEY`
- `OPENAI_MODEL` or `MODEL`
- `OPENAI_BASE_URL`
- `OPENAI_API_KEY_HEADER`
- `OPENAI_STORE`
- `OPENAGENTIC_SDK_HOME`
- `OPENAGENTIC_AGENTS_HOME`
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `TAVILY_API_KEY`
- `TAVILY_URL`

## Tests and validation

### Offline

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
rebar3 eunit
```

### Optional online suites

```powershell
.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E
.\scripts\e2e-web-online.ps1 -EnableProxy -SkipRebar3Verify -E2E
```

### Kotlin parity helper

```powershell
.\scripts\kotlin-parity-check.ps1
```

## Specs and design notes

- Workflow engine spec: `docs/spec/workflow-engine.md`
- Workflow engine spec (Chinese): `docs/spec/workflow-engine.zh_ch.md`
- Agent-host protocol: `docs/spec/agent-host-protocol.md`
- Agent-host protocol (Chinese): `docs/spec/agent-host-protocol.zh_ch.md`
- Workflow DSL schema: `docs/spec/workflow-dsl-schema.md`
- Workflow DSL schema (Chinese): `docs/spec/workflow-dsl-schema.zh_ch.md`

## Troubleshooting

### `401` / missing API key

- Ensure `.env` exists in the project directory.
- Ensure `OPENAI_API_KEY` is set.
- If you use a gateway, set `OPENAI_API_KEY_HEADER` correctly.

### `rebar3` or Erlang not found

Run the env script first in the same terminal:

```powershell
. .\scripts\erlang-env.ps1 -SkipRebar3Verify
```

### Output is too dense

- Use `--no-stream` for long outputs
- Use `--no-color` or `NO_COLOR=1`
- Keep `--render-markdown` enabled for non-stream mode

### Web search looks weak

- Configure `TAVILY_API_KEY` for better search results
- Without Tavily, the tool falls back to DuckDuckGo HTML parsing
