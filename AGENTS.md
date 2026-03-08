# Agent Notes: openagentic-sdk-erlang

## Project Overview

`openagentic-sdk-erlang` is the Erlang/OTP sibling of `openagentic-sdk-kotlin`.
The repo currently contains one main product: a local-first agent runtime + workflow engine + lightweight web control plane under `apps/openagentic_sdk/`.

## Quick Commands

Prerequisites:
- Erlang/OTP 28
- `rebar3`
- Windows PowerShell 7.x recommended
- In mainland network environments, proxy is usually needed

Recommended Windows PowerShell session bootstrap:

- Set env + proxy: `. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify`
- Set env without proxy: `. .\scripts\erlang-env.ps1 -SkipRebar3Verify`
- Compile + run tests: `rebar3 eunit`
- Start Erlang shell: `rebar3 shell`
- Run parity helper: `.\scripts\kotlin-parity-check.ps1`
- Optional online E2E: `.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E`

Inside `rebar3 shell`:
- One-shot query: `openagentic_cli:main(["run", "Hello"]).`
- Chat mode: `openagentic_cli:main(["chat"]).`
- Workflow mode: `openagentic_cli:main(["workflow", "--dsl", "workflows/three-provinces-six-ministries.v1.json", "Plan X"]).`
- Web UI: `openagentic_cli:main(["web"]).`

## Shell Gate

- In this repo, agents must explicitly invoke `pwsh.exe` for shell work.
- Do not fall back to `powershell.exe` 5.x, even for read-only text inspection.
- If `pwsh.exe` is unavailable, stop immediately and report the blocker instead of continuing with `powershell.exe`.

## Architecture Overview

### Areas

- Core SDK/runtime:
  - facade: `apps/openagentic_sdk/src/openagentic_sdk.erl`
  - runtime/tool-loop: `apps/openagentic_sdk/src/openagentic_runtime.erl`
  - provider protocol selection: `apps/openagentic_sdk/src/openagentic_provider_protocol.erl`
  - default provider implementations:
    - `apps/openagentic_sdk/src/openagentic_openai_responses.erl`
    - `apps/openagentic_sdk/src/openagentic_openai_chat_completions.erl`
- CLI:
  - entry: `apps/openagentic_sdk/src/openagentic_cli.erl`
- Workflow subsystem:
  - DSL loader/validator: `apps/openagentic_sdk/src/openagentic_workflow_dsl.erl`
  - execution engine: `apps/openagentic_sdk/src/openagentic_workflow_engine.erl`
  - queue/cancel/stall manager: `apps/openagentic_sdk/src/openagentic_workflow_mgr.erl`
  - default workflow: `workflows/three-provinces-six-ministries.v1.json`
- Web control plane:
  - server entry: `apps/openagentic_sdk/src/openagentic_web.erl`
  - handlers: `apps/openagentic_sdk/src/openagentic_web_api_*.erl`
  - static UI: `apps/openagentic_sdk/priv/web/`
- Tools:
  - registry: `apps/openagentic_sdk/src/openagentic_tool_registry.erl`
  - schema generation: `apps/openagentic_sdk/src/openagentic_tool_schemas.erl`
  - built-ins: `apps/openagentic_sdk/src/openagentic_tool_*.erl`
- Skills / slash commands:
  - skills indexer: `apps/openagentic_sdk/src/openagentic_skills.erl`
  - skill tool: `apps/openagentic_sdk/src/openagentic_tool_skill.erl`
  - slash command tool: `apps/openagentic_sdk/src/openagentic_tool_slash_command.erl`

### Data Flow

```text
CLI / Web UI / Workflow API
  -> runtime or workflow engine
    -> provider request + SSE parsing
      -> permission gate
        -> tool registry + tool modules
          -> session store append
            -> CLI formatter / Web SSE / workspace APIs
```

### Persistence

- Session root:
  - default from `OPENAGENTIC_SDK_HOME`
  - fallback: `%USERPROFILE%\.openagentic-sdk`
- Session files:
  - `sessions/<session_id>/meta.json`
  - `sessions/<session_id>/events.jsonl`
- Skills roots (later wins / more local wins):
  - `OPENAGENTIC_AGENTS_HOME` (default `%USERPROFILE%\.agents`)
  - `OPENAGENTIC_SDK_HOME`
  - project root
  - `project/.claude`
- Slash commands:
  - `project/.opencode/commands/*.md`
  - `project/.claude/commands/*.md`
  - `%USERPROFILE%\.config\opencode\commands\*.md`

## Current Functional Surface (as of 2026-03-07)

What is actually implemented in code today:

- `openagentic_sdk:query/2` public facade
- OpenAI Responses is the default path
- OpenAI Chat Completions legacy mode is still supported via protocol override
- time-context injection is active in runtime and workflow sessions
- session persistence is local-first and append-only
- default tools include FS, shell, web, skills, slash commands, subagents, todo, and question tools
- permission default auto-approves safe read-only tools and workspace-scoped writes
- `Skill` parses front matter / summary / checklist from `SKILL.md`
- `SlashCommand` loads opencode-compatible command templates
- `Task` includes built-in `explore` and `research` subagents
- workflow DSL supports guards, contracts, tool policy, fanout/join, retry policy, queue/continue/cancel/stall handling
- local web server exposes workflow APIs, SSE event tailing, workspace read, and question answering
- hook events and tool output artifact externalization are implemented
- `WebFetch` has hostname safety checks and bounded output modes
- `WebSearch` uses Tavily when configured and DuckDuckGo HTML fallback otherwise
- `rebar3 eunit` currently passes with `175 tests, 0 failures`

## Runtime Config

Use environment variables or a local `.env` in the project root.
Do not commit real secrets.

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

Windows repo-local `.env` is loaded by `openagentic_cli` after resolving the project directory.
Do not read, print, or commit real `.env` contents into the repo, tests, or logs.

## Code Style & Conventions

- Language: Erlang/OTP 28
- Build config: `rebar.config`
- Compiler stance: warnings are errors (`{erl_opts, [debug_info, warnings_as_errors]}`)
- JSON handling: prefer the project wrappers (`openagentic_json`, parsing helpers); do not scatter raw encoder/decoder calls across new modules
- Public API shape: prefer `{ok, Value} | {error, Reason}`
- Naming:
  - modules: `openagentic_*`
  - map keys / JSON-like fields: `snake_case` where possible
  - test modules: `*_test.erl`
- File organization:
  - runtime/provider/tool/web/workflow logic are already split by module family; keep new code in the matching family rather than creating mixed “god modules”
  - add eunit tests under `apps/openagentic_sdk/test/` for behavior changes
- Documentation policy:
  - if public behavior, workflow semantics, tool behavior, or setup commands change, update `README.md`, `README.zh_ch.md`, and relevant `docs/spec/*`
  - if agent workflow or repo-operating assumptions change, update `AGENTS.md`

## Safety & Conventions

- Do not read or print the real `.env` contents unless the task explicitly requires it and the output stays local/non-public.
  - Why: this repo may contain real API keys or gateway URLs locally.
  - Do instead: document variable names only; use placeholders in docs.
  - Verify: diff shows no secrets and no key-like strings.

- Do not move cache / dependency / session heavy data back to `C:`.
  - Why: the repo is explicitly configured to keep Erlang caches and runtime data on `E:`.
  - Do instead: use `.\scripts\erlang-env.ps1` and preserve `ERLANG_HOME`, `REBAR_BASE_DIR`, `REBAR_CACHE_DIR`, `HEX_HOME`, `OPENAGENTIC_SDK_HOME`.
  - Verify: env values point to `E:\...` in the current shell.

- Do not perform destructive filesystem operations without confirmation.
  - Why: sessions, workflow outputs, and local fixtures can be hard to reconstruct.
  - Do instead: ask before `Remove-Item -Recurse -Force`, mass deletes, or directory rewrites.
  - Verify: user confirmation exists in chat history when a destructive action is required.

- Do not rewrite UTF-8 repo files through Windows PowerShell 5.1 text output primitives.
  - Why: Codex shell invocations can land on `powershell.exe` 5.1 even when PowerShell 7 is installed. In that mode, `Set-Content` writes ACP/ANSI for new files, `>` / `Out-File` write UTF-16LE, and piping text into `python -` is constrained by `$OutputEncoding` (observed `us-ascii`). This corrupts UTF-8 Chinese text and shows up as mojibake, `??`, BOMs, or NUL bytes.
  - Gate: agents must use `pwsh.exe` for repository text reads/writes and must not fall back to `powershell.exe` 5.x.
  - Do instead: prefer `pwsh.exe` for text-writing tasks, or use Python `Path.read_text(..., encoding='utf-8')` and `Path.write_text(..., encoding='utf-8')` with explicit newline handling.
  - Do instead: keep shell-side scripts ASCII-only when launching Python from PowerShell; use Unicode escapes or a temporary `.py` file instead of piping non-ASCII source text through PowerShell here-strings or pipelines.
  - Do instead: avoid `Set-Content`, `Add-Content`, `Out-File`, `>`, and `>>` for source, HTML/CSS/JS, Markdown, or docs edits unless encoding is explicitly controlled and then verified.
  - Verify: inspect `git diff --text -- <file>` and, if needed, raw bytes to confirm there is no UTF-16 BOM, no NUL bytes, and no unexpected `?` replacements.

- Do not claim behavior is implemented just because a plan or docs mention it.
  - Why: this repo contains forward-looking plans under `docs/plans/` that can drift ahead of code.
  - Do instead: scan `apps/openagentic_sdk/src/`, `apps/openagentic_sdk/test/`, and run at least `rebar3 eunit` before updating docs.
  - Verify: cite code paths and fresh command output in your handoff.

- Do not add tests outside the established eunit layout unless a new test harness is explicitly requested.
  - Why: the repo currently uses eunit as the default verified local gate.
  - Do instead: place new tests in `apps/openagentic_sdk/test/`.
  - Verify: `rebar3 eunit` still passes.

### Security Considerations

- Secrets: never hardcode secrets; use env vars or local `.env` only
- Network: proxy may be required; prefer session-local `HTTP_PROXY` / `HTTPS_PROXY`
- Web tools: keep localhost/private-network blocking intact for `WebFetch`
- Dependencies: do not add new deps casually; this repo is intentionally small (`jsone`, `cowboy`)
- User data: sessions may contain prompts, outputs, and tool traces; do not paste them into public docs unless sanitized

## Testing Strategy

### Full local gate
- `rebar3 eunit`

### Environment bootstrap
- `. .\scripts\erlang-env.ps1 -SkipRebar3Verify`
- or `. .\scripts\erlang-env.ps1 -EnableProxy -SkipRebar3Verify`

### Optional online validation
- `.\scripts\e2e-online-suite.ps1 -EnableProxy -SkipRebar3Verify -E2E`
- `.\scripts\e2e-web-online.ps1 -EnableProxy -SkipRebar3Verify -E2E`

### Kotlin parity helper
- `.\scripts\kotlin-parity-check.ps1`

### Rules
- Add or update tests for code you change, even if not explicitly requested
- Prefer the smallest relevant test first, then `rebar3 eunit`
- Treat `docs/plans/` as design input, not proof of implementation

## Kotlin Parity Workflow

When the task is Kotlin parity work, follow this order:

1. Scan Kotlin ↔ Erlang differences
2. Write each gap into `docs/plans/2026-03-04-kotlin-parity-backlog.md` as a checklist item
3. Implement one gap at a time
4. Run the relevant gate (`rebar3 eunit`, parity helper, etc.)
5. Mark the backlog item done with evidence
6. Move to the next gap

Do not implement parity items first and backfill the backlog later.

## Scope & Precedence

- Root `AGENTS.md` applies to the whole repository by default
- If a subdirectory gets its own `AGENTS.md`, the nearer file wins for that subtree
- User instructions in chat override repo docs
- Keep this file below Codex project-doc limits; if it grows too large, split rules into subdirectory `AGENTS.md` files

## Completion Reminder

After completing a task, send a short APNs push via `apn-pushtool`.
Title: repo name.
Body: short, non-sensitive summary (<= 10 Chinese characters preferred).
